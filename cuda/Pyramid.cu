#include <cfloat>

#include "Error.hpp"
#include "Pyramid.hpp"
#include "Kernels.hpp"

void Pyramid::intersect(float *d_rx, float *d_ry, float *d_rz,
                        float *d_vx, float *d_vy, float *d_vz,
                        const int N, const int blockSize, const int numBlocks,
                        std::vector<float> &int_times, std::vector<float> &int_coords)
{
    /* The device float array "device_time" is allocated on device, and
     * its elements' values are set to -5.
     * This array will store the times calculated by the intersectPyramid
     * kernel.
     */
    float *device_time;
    CudaErrchk( cudaMalloc(&device_time, 5*N*sizeof(float)) );
    initArray<<<numBlocks, blockSize>>>(device_time, 5*N, -5);
    CudaErrchkNoCode();
    /* The device float array "intersect" is allocated on device, and
     * its elements' values are set to FLT_MAX.
     * This array will store the intersection coordinates calculated
     * by the intersectPyramid kernel.
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
    intersectPyramid<<<numBlocks, blockSize>>>(d_rx, d_ry, d_rz,
                                               d_vx, d_vy, d_vz,
                                               edgeX, edgeY, height,
                                               N, device_time, intersect);
    /* This code is for testing the output of intersectPyramid.
     * It will be removed once the intersectTriangle function works.
     */
    //CudaDeviceSynchronize();
    //printf("\n\nEnd Kernel.\n");
    /*std::vector<float> tmp;
    tmp.resize(5*N);
    CudaErrchk( cudaMemcpy(tmp.data(), device_time, 5*N*sizeof(float), cudaMemcpyDeviceToHost) );
    for (int i = 0; i < (int)(tmp.size()); i++)
    {
        if (i % 5 == 0)
        {
            printf("Ray Index %i:\n", i/5);
        }
        printf("    Offset = %i: Time = %f\n", (i%5), tmp[i]);
    }*/
    //cudaDeviceSynchronize();
    simplifyTimes<<<numBlocks, blockSize>>>(device_time, N, 5, simp_times);
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