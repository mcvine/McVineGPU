#include <cfloat>

#include "Box.hpp"
#include "Error.hpp"
#include "Kernels.hpp"

// See the corresponding comment in AbstractShape.hpp
/*void Box::accept(UnaryVisitor &v)
{
    throw "This function is not yet implemented.\n";
}*/

void Box::intersect(float *d_rx, float *d_ry, float *d_rz,
                    float *d_vx, float *d_vy, float *d_vz,
                    const int N, const int blockSize, const int numBlocks,
                    std::vector<float> &int_times, std::vector<float> &int_coords)
{
    /* The device float array "device_time" is allocated on device, and
     * its elements' values are set to -5.
     * This array will store the times calculated by the intersectBox
     * kernel.
     */
    float *device_time;
    CudaErrchk( cudaMalloc(&device_time, 6*N*sizeof(float)) );
    initArray<<<numBlocks, blockSize>>>(device_time, 6*N, -5);
    CudaErrchkNoCode();
    /* The device float array "intersect" is allocated on device, and
     * its elements' values are set to FLT_MAX.
     * This array will store the intersection coordinates calculated 
     * by the intersectBox kernel.
     */
    float *intersect;
    CudaErrchk( cudaMalloc(&intersect, 6*N*sizeof(float)) );
    initArray<<<numBlocks, blockSize>>>(intersect, 6*N, FLT_MAX);
    CudaErrchkNoCode();
    /* The device float array "simp_times" is allocated on device, and
     * its elements' values are set to -5.
     * This array will store the output of the simplifyTimes kernel.
     */
    float *simp_times;
    CudaErrchk( cudaMalloc(&simp_times, 2*N*sizeof(float)) );
    initArray<<<numBlocks, blockSize>>>(simp_times, 2*N, -5);
    CudaErrchkNoCode();
    // These vectors are resized to match the size of the arrays above.
    int_times.resize(2*N);
    int_coords.resize(6*N);
    // The kernels are called to perform the intersection calculation.
    intersectBox<<<numBlocks, blockSize>>>(d_rx, d_ry, d_rz,
                                           d_vx, d_vy, d_vz,
                                           X, Y, Z,
                                           N, device_time, intersect);
    simplifyTimes<<<numBlocks, blockSize>>>(device_time, N, 6, simp_times);
    CudaErrchkNoCode();
    /* The data from simp_times and intersect is copied into
     * int_times and int_coords respectively.
     */
    float *it = int_times.data();
    float *ic = int_coords.data();
    CudaErrchk( cudaMemcpy(it, simp_times, 2*N*sizeof(float), cudaMemcpyDeviceToHost) );
    CudaErrchk( cudaMemcpy(ic, intersect, 6*N*sizeof(float), cudaMemcpyDeviceToHost) );
    /* The device memory allocated at the beginning of the function
     * is freed.
     */
    CudaErrchk( cudaFree(device_time) );
    CudaErrchk( cudaFree(intersect) );
    CudaErrchk( cudaFree(simp_times) );
}