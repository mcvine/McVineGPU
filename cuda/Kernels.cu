#include <cstdio>

#include "Kernels.hpp"

__global__ void initArray(float *data, int size, const float val)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < size; i += stride)
    {
        data[i] = val;
    }
}

__device__ float dot(float ax, float ay, float az,
                     float bx, float by, float bz)
{
    return ax*bx + ay*by + az*bz;
}

__device__ void cross(float ax, float ay, float az,
                      float bx, float by, float bz,
                      float *cx, float *cy, float *cz)
{
    *cx = ay*bz - az*by;
    *cy = az*bx - ax*bz;
    *cz = ax*by - by*bx;
    return;
}

__device__ void intersectRectangle(float* ts, float* pts,
                                   float x, float y, float z, float zdiff,
                                   float va, float vb, float vc, 
                                   const float A, const float B,
                                   const int key, const int groupSize, 
                                   const int off1, int &off2)
{
    /* Subtracting zdiff from z effectively makes the rectangle
     * be in the same plane as the local (function-specific) XY plane.
     */
    z -= zdiff;
    /* Calculates t using the basic kinematic equation z1 = z + vz*t
     * Note that z1 is always 0 due to the subtraction above.
     */
    float t = (0-z)/vc;
    /* Uses the same kinematic equation as above to calculate the local
     * x and y intersection coordinates from the time.
     */
    float r1x = x+va*t; 
    float r1y = y+vb*t;
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    // This if-statement ensures the intersection is within the rectangle.
    if (fabsf(r1x) < (A/2) && fabsf(r1y) < (B/2))
    {
        /* The key parameter represents the relationship between this
         * function's local XYZ-coordinate system and the coordinate
         * system of the overall solid. If key is 0, the coordinate
         * systems are the same. If key is 1, the local X matches the
         * solid's Y; the local Y matches the solid's Z; and the local
         * Z matches the solid's X. If key is 2, the local X matches the
         * solid's Z; the local Y matches the solid's X; and the local
         * Z matches the solid's Y.
         * The intersection coordinates in the solid's coordinate system
         * are stored in ix, iy, and iz.
         */
        float ix, iy, iz;
        if (key == 0)
        {
            ix = r1x;
            iy = r1y;
            iz = zdiff;
        }
        else if (key == 1)
        {
            iy = r1x;
            iz = r1y;
            ix = zdiff;
        }
        else
        {
            iz = r1x;
            ix = r1y;
            iy = zdiff;
        }
        /* This if-statement ensures at most 2 intersection
         * points are stored.
         */
        if (off2 == 0 || off2 == 3)
        {
            // Stores ix, iy, and iz in the pts array.
            pts[6*index + off2] = ix;
            pts[6*index + off2 + 1] = iy;
            pts[6*index + off2 + 2] = iz;
            // Increases off2 to prevent data overwrite.
            off2 += 3;
            //printf("Rectangle: index = %i    off2 = %i\n", index, off2);
        }
        ts[off1 + index*groupSize] = t;
    }
    /* If the intersection coordinates do not fall within the rectangle,
     * a time of -1 is assigned to the function call's element in ts.
     * Additionally, no intersection coordinates are stored in pts.
     */
    else
    {
        ts[off1 + index*groupSize] = -1;
    }
}

__device__ void intersectCylinderSide(float *ts, float *pts,
                                      float x, float y, float z,
                                      float vx, float vy, float vz,
                                      const float r, const float h, 
                                      int &offset)
{
    /* NOTE: This function is based on the corresponding function
     *       from ArrowIntersector in McVine. As a result, the
     *       solveQuadratic function below is not used here.
     *       It will likely be refactored later to include
     *       said function.
     */
    /* Calculate the a, b, and c parameters for the quadratic formula.
     * The parameters are generated by substituting the x and y
     * components of the neutron's ray equation into the equation for
     * a circular Cylinder. The final equation is:
     *    (vx^2 + vy^2)*t^2 + 2(x*vx + y*vy)*t + (x^2 + y^2 + r^2) = 0
     *
     * Note: The 2 that should be part of b base on the above equation
     *       is not included because it can be combined with the
     *       4 from the 4ac part of the quadratic formula. This combination
     *       is then cancelled by the 2 in the denominator of the
     *       quadratic formula.
     */ 
    float a = vx*vx + vy*vy;
    float b = x*vx + y*vy;
    float c = x*x+y*y - r*r;
    // discr is the discriminant of the quadratic formula (b^2 - 4ac).
    float discr = b*b - a*c;
    float t;
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    /* If the discriminant is less than 0, then there are no real roots
     * to the quadratic equation that defines t. As a result, the times
     * in ts are set to the default no-solution value of -1.
     */
    if (discr < 0)
    {
        ts[4*index + 2] = -1;
        ts[4*index + 3] = -1;
        return;
    }
    /* If the discriminant equals 0, there can only be one possible
     * time and, thus, only one possible intersection with the side
     * of the Cylinder.
     */
    else if (discr == 0)
    {
        /* Calculates time from a simplified, case-specific version of the
         * quadratic formula.
         */
        t = -b/a;
        /* ts[4*index + 3] stores the time of the second intersection
         * between the neutron and the side of the Cylinder. Since a
         * second intersection is not possible in this case, this element
         * of ts is given a default value of -1.
         */
        ts[4*index + 3] = -1;
        /* The neutron only intersects the side of the Cylinder 
         * if the absolute value of the Z-coordinate of the intersection
         * point is less than h/2.
         */
        if (fabsf(z+vz*t) < h/2)
        {
            ts[4*index + 2] = t;
            // See intersectRectangle
            if (offset == 0 || offset == 3)
            {
                pts[6*index + offset] = x+vx*t;
                pts[6*index + offset + 1] = y+vy*t;
                pts[6*index + offset + 2] = z+vz*t;
                offset += 3;
            }
        }
        else
        {
            ts[4*index + 2] = -1;
        }
    }
    // Used to prevent memory corruption.
    __syncthreads();
    // i is used to track the offset for ts
    int i = 2;
    // t is calculated using the quadratic formula with +
    discr = sqrtf(discr);
    t = (-b+discr)/a;
    if (fabsf(z+vz*t) < h/2)
    {
        ts[4*index + i] = t;
        i++;
        if (offset == 0 || offset == 3)
        {
            pts[6*index + offset] = x+vx*t;
            pts[6*index + offset + 1] = y+vy*t;
            pts[6*index + offset + 2] = z+vz*t;
            offset += 3;
        }
    }
    // t is calculated using the quadratic formula with -
    t = (-b-discr)/a;
    if (fabsf(z+vz*t) < h/2)
    {
        ts[4*index + i] = t;
        i++;
        if (offset == 0 || offset == 3)
        {
            pts[6*index + offset] = x+vx*t;
            pts[6*index + offset + 1] = y+vy*t;
            pts[6*index + offset + 2] = z+vz*t;
            offset += 3;
        }
    }
    /* If i < 4, at least one time was not set in ts.
     * This if-statement will set the time of these unset
     * elements to -1.
     */
    if (i < 4)
    {
        for (int j = i; j < 4; j++)
        {
            ts[4*index + j] = -1;
        }
    }
    // Again used to prevent memory corruption
    __syncthreads();
}

__device__ void intersectCylinderTopBottom(float *ts, float *pts,
                                           float x, float y, float z,
                                           float vx, float vy, float vz,
                                           const float r, const float h,
                                           int &offset)
{
    // Calculates values needed to evaluate and validate the time.
    float r2 = r*r;
    float hh = h/2;
    float x1, y1;
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    /* Time is calculated by dividing the Z-distance the neutron has
     * to travel to reach the Z-coordinate of the top of the Cylinder
     * by the Z component of the neutron's velocity.
     */
    float t = (hh-z)/vz;
    /* Uses basic kinematics to determine the X and Y 
     * coordinates of the potential intersection point.
     */
    x1 = x + vx*t;
    y1 = y + vy*t;
    /* If the intersection point is a valid solution to the
     * equation defining the circular top of the Cylinder, 
     * the time and intersection coordinates are stored in
     * ts and pts respectively.
     */
    if (x1*x1 + y1*y1 <= r2)
    {
        ts[4*index] = t;
        if (offset == 0 || offset == 3)
        {
            pts[6*index + offset] = x1;
            pts[6*index + offset + 1] = y1;
            pts[6*index + offset + 2] = hh;
            offset += 3;
        }
    }
    // Otherwise, the time is stored as -1.
    else
    {
        ts[4*index] = -1;
    }
    // Repeat the above step for the bottom face of the Cylinder.
    t = (-hh-z)/vz;
    x1 = x + vx*t;
    y1 = y + vy*t;
    if (x1*x1 + y1*y1 <= r2)
    {
        ts[4*index + 1] = t;
        if (offset == 0 || offset == 3)
        {
            pts[6*index + offset] = x1;
            pts[6*index + offset + 1] = y1;
            pts[6*index + offset + 2] = -hh;
            offset += 3;
        }
    }
    else
    {
        ts[4*index + 1] = -1;
    }
}

/* This function is not yet working.
 * As a result, it will not yet be commented.
 */
__device__ void intersectTriangle(float *ts, float *pts,
                                  const float x, const float y, const float z,
                                  const float vx, const float vy, const float vz,
                                  const float aX, const float aY, const float aZ, 
                                  const float bX, const float bY, const float bZ,
                                  const float cX, const float cY, const float cZ,
                                  const int off1, int &off2)
{   
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    float abX = bX - aX, abY = bY - aY, abZ = bZ - aZ;
    float acX = cX - aX, acY = cY - aY, acZ = cZ - aZ;
    float nX, nY, nZ;
    cross(abX, abY, abZ, acX, acY, acZ, &nX, &nY, &nZ);
    float nLength = fabsf(nX)*fabsf(nX)+fabsf(nY)*fabsf(nY)+fabsf(nZ)*fabsf(nZ);
    nLength = sqrtf(nLength);
    nX /= nLength; nY /= nLength; nZ /= nLength;
    float ndv = dot(nX, nY, nZ, vx, vy, vz);
    if (fabsf(ndv) < 1e-10)
    {
        ts[5*index + off1] = -1;
        return;
    }
    float d = dot(nX, nY, nZ, aX, aY, aZ);
    float t = (dot(nX, nY, nZ, x, y, z) + d) / ndv;
    if (t < 0)
    {
        printf("time < 0\n");
        ts[5*index + off1] = -1;
        return;
    }
    float pX = x + vx*t, pY = y + vy*t, pZ = z + vz*t;
    float apX = pX - aX, apY = pY - aY, apZ = pZ - aZ;
    float edge1X = cX - bX, edge1Y = cY - bY, edge1Z = cZ - bZ;
    float bpX = pX - bX, bpY = pY - bY, bpZ = pZ - bZ;
    float cpX = pX - cX, cpY = pY - cY, cpZ = pZ - cZ;
    float c0X, c0Y, c0Z, c1X, c1Y, c1Z, c2X, c2Y, c2Z;
    cross(abX, abY, abZ, apX, apY, apZ, &c0X, &c0Y, &c0Z);
    cross(edge1X, edge1Y, edge1Z, bpX, bpY, bpZ, &c1X, &c1Y, &c1Z);
    cross(-acX, -acY, -acZ, cpX, cpY, cpZ, &c2X, &c2Y, &c2Z);
    if (dot(nX, nY, nZ, c0X, c0Y, c0Z) < 0 ||
        dot(nX, nY, nZ, c1X, c1Y, c1Z) < 0 ||
        dot(nX, nY, nZ, c2X, c2Y, c2Z) < 0)
    {
        ts[5*index+off1] = -1;
        return;
    }
    ts[5*index + off1] = t;
    if (off2 == 0 || off2 == 3)
    {
        pts[6*index + off2] = pX;
        pts[6*index + off2 + 1] = pY;
        pts[6*index + off2 + 2] = pZ;
        off2 += 3;
    }
    //__syncthreads();
    return;
    /*int index = blockIdx.x * blockDim.x + threadIdx.x;
    float abX = bX - aX, abY = bY - aY, abZ = bZ - aZ;
    float acX = cX - aX, acY = cY - aY, acZ = cZ - aZ;
    float nX, nY, nZ;
    cross(abX, abY, abZ, acX, acY, acZ, &nX, &nY, &nZ);
    float nLength = fabsf(nX)*fabsf(nX)+fabsf(nY)*fabsf(nY)+fabsf(nZ)*fabsf(nZ);
    nLength = sqrtf(nLength);
    nX /= nLength; nY /= nLength; nZ /= nLength;
    float d = dot(nX, nY, nZ, aX, aY, aZ);
    float v_p = dot(nX, nY, nZ, vx, vy, vz);
    if (fabsf(v_p) < 1e-10)
    {
        ts[5*index + off1] = -1;
        return;
    }
    float r_p = dot(nX, nY, nZ, x, y, z);
    float t = (d - r_p)/v_p;
    //printf("index = %i\n    abX = %f abY = %f abZ = %f\n    acX = %f acY = %f acZ = %f\n    nX = %f nY = %f nZ = %f\n    d = %f r_p = %f v_p = %f\n    t = %f\n", index, abX, abY, abZ, acX, acY, acZ, nX, nY, nZ, d, r_p, v_p, t);
    float pX = x + vx*t, pY = y + vy*t, pZ = z + vz*t;
    float apX = pX - aX, apY = pY - aY, apZ = pZ - aZ;
    float ncX, ncY, ncZ;
    cross(nX, nY, nZ, acX, acY, acZ, &ncX, &ncY, &ncZ);
    float c1 = dot(apX, apY, apZ, ncX, ncY, ncZ)/dot(abX, abY, abZ, ncX, ncY, ncZ);
    if (c1 < 0)
    {
        ts[5*index + off1] = -1;
        return;
    }
    float nbX, nbY, nbZ;
    cross(nX, nY, nZ, abX, abY, abZ, &nbX, &nbY, &nbZ);
    float c2 = dot(apX, apY, apZ, nbX, nbY, nbZ)/dot(acX, acY, acZ, nbX, nbY, nbZ);
    if (c2 < 0)
    {
        ts[5*index + off1] = -1;
        return;
    }
    if (c1+c2 > 1)
    {
        ts[5*index + off1] = -1;
        return;
    }
    // Set time to actual value and record pX, pY, and pZ as int pts.
    // ascii(T) = 84
    ts[5*index + off1] = t + 84;
    if (off2 == 0 || off2 == 3)
    {
        pts[6*index + off2] = pX;
        pts[6*index + off2 + 1] = pY;
        pts[6*index + off2 + 2] = pZ;
        //printf("index = %i: time = %f\n    x = %f y = %f z = %f\n    vx = %f vy = %f vz = %f\n    pX = %f pY = %f pZ = %f\n    pts[%i] = %f pts[%i] = %f pts[%i] = %f\n", index, t, x, y, z, vx, vy, vz, pX, pY, pZ, 6*index+off2, pts[6*index + off2], 6*index+off2+1, pts[6*index + off2+1], 6*index+off2+2, pts[6*index + off2+2]);
        off2 += 3;
        //printf("Triangle: index = %i    off2 = %i\n", index, off2);
    }
    __syncthreads();*/
}

/*__device__ void calculateQuadCoef(float x, float vx, float vy, float vz,
                                  float dist, float &disc,
                                  float &a, float &b, float &c)
{
    a = 1 + (vy/vx)*(vy/vx) + (vz/vx)*(vz/vx);
    b = -2*(1 + ((x*vy*vy)/(vx*vx)) + ((x*vz*vz)/(vx*vx)));
    c = x*x + ((x*vy)/vx)*((x*vy)/vx) + ((x*vz)/vx)*((x*vz)/vx);
    c -= dist*dist;
    disc = b*b - 4*a*c;
    return;
}*/

__device__ bool solveQuadratic(float a, float b, float c, float &x0, float &x1)
{
    // Calculates the discriminant and returns false if it is less than 0.
    float discr = b*b - 4*a*c;
    if (discr < 0)
    {
        return false;
    }
    else
    {
        /* This process ensures that there is little to no roundoff error
         * in the evaluation of the quadratic formula.
         * This process defines a value 
         * q = -0.5 * (b + sign(b)*sqrt(b^2 - 4ac)).
         * If you define x0 = q/a (producing the standard quadratic
         * formula), x1 can be defined as c/q by multiplying the
         * other form of the formula (+/- -> -sign(b)) by
         * ((-b + sign(b)*sqrt(discr))/(-b + sign(b)*sqrt(discr))).
         */
        float q = (b > 0) ? 
                  (-0.5 * (b + sqrtf(discr))) :
                  (-0.5 * (b - sqrtf(discr)));
        x0 = q/a;
        x1 = c/q;
    }
    // This simply ensures that x0 < x1.
    if (x0 > x1)
    {
        float tmp = x0;
        x0 = x1;
        x1 = tmp;
    }
    return true;
}

__global__ void intersectBox(float* rx, float* ry, float* rz,
                             float* vx, float* vy, float* vz,
                             const float X, const float Y, const float Z, 
                             const int N, float* ts, float* pts)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    // This is done to prevent excess threads from interfering in the code.
    if (index < N)
    {
        /* The offset variable is used to ensure only
         * 2 intersection points are recorded.
         */
        int offset = 0;
        /* If the neutron does not move in the Z-direction, there will
         * never be an intersection with the top or bottom. So,
         * the times for top and bottom intersection are set to -1.
         * Otherwise, the intersectRectangle function is used to
         * calculate any potential intersection times and points.
         */
        if (vz[index] != 0)
        {
            intersectRectangle(ts, pts, rx[index], ry[index], rz[index], Z/2, vx[index], vy[index], vz[index], X, Y, 0, 6, 0, offset);
            intersectRectangle(ts, pts, rx[index], ry[index], rz[index], -Z/2, vx[index], vy[index], vz[index], X, Y, 0, 6, 1, offset);
        }
        else
        {
            ts[index*6] = -1;
            ts[index*6 + 1] = -1;
        }
        /* If the neutron does not move in the X-direction, there will
         * never be an intersection with the sides parallel to the YZ plane.
         * So, the times for these intersections are set to -1.
         * Otherwise, the intersectRectangle function is used to
         * calculate any potential intersection times and points.
         */
        if (vx[index] != 0)
        {
            intersectRectangle(ts, pts, ry[index], rz[index], rx[index], X/2, vy[index], vz[index], vx[index], Y, Z, 1, 6, 2, offset);
            intersectRectangle(ts, pts, ry[index], rz[index], rx[index], -X/2, vy[index], vz[index], vx[index], Y, Z, 1, 6, 3, offset);
        }
        else
        {
            ts[index*6 + 2] = -1;
            ts[index*6 + 3] = -1;
        }
        /* If the neutron does not move in the Y-direction, there will
         * never be an intersection with the sides parallel to the XZ plane.
         * So, the times for these intersections are set to -1.
         * Otherwise, the intersectRectangle function is used to
         * calculate any potential intersection times and points.
         */
        if (vy[index] != 0)
        {
            intersectRectangle(ts, pts, rz[index], rx[index], ry[index], Y/2, vz[index], vx[index], vy[index], Z, X, 2, 6, 4, offset);
            intersectRectangle(ts, pts, rz[index], rx[index], ry[index], -Y/2, vz[index], vx[index], vy[index], Z, X, 2, 6, 5, offset);
        }
        else
        {
            ts[index*6 + 4] = -1;
            ts[index*6 + 5] = -1;
        }
    }
}

__global__ void intersectCylinder(float *rx, float *ry, float *rz,
                                  float *vx, float *vy, float *vz,
                                  const float r, const float h,
                                  const int N, float *ts, float *pts)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    // This is done to prevent excess threads from interfering in the code.
    if (index < N)
    {
        /* The offset variable is used to ensure only
         * 2 intersection points are recorded.
         */
        int offset = 0;
        /* The actual intersection calculations are carried out
         * by these two helper functions.
         */
        intersectCylinderTopBottom(ts, pts, rx[index], ry[index], rz[index], vx[index], vy[index], vz[index], r, h, offset);
        intersectCylinderSide(ts, pts, rx[index], ry[index], rz[index], vx[index], vy[index], vz[index], r, h, offset);
    }
}

__global__ void intersectPyramid(float *rx, float *ry, float *rz,
                                 float *vx, float *vy, float *vz,
                                 const float X, const float Y, const float H,
                                 const int N, float *ts, float *pts)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    // This is done to prevent excess threads from interfering in the code.
    if (index < N)
    {
        /* The offset variable is used to ensure only
         * 2 intersection points are recorded.
         */
        int offset = 0;
        /* If the neutron doesn't move in the Z-direction, it will
         * never intersect the Pyramid's base. If it might intersect,
         * the intersectRectangle function is used to determine any
         * intersection point.
         */
        if (vz[index] != 0)
        {
            intersectRectangle(ts, pts, rx[index], ry[index], rz[index], -H, vx[index], vy[index], vz[index], X, Y, 0, 5, 0, offset);
        }
        /* These calls to intersectTriangle determine if there are
         * any intersections between the neutron and the triangular
         * faces of the Pyramid.
         */
        intersectTriangle(ts, pts,
                          rx[index], ry[index], rz[index],
                          vz[index], vy[index], vz[index],
                          0, 0, 0, X/2, Y/2, -H, X/2, -Y/2, -H,
                          1, offset);
        intersectTriangle(ts, pts,
                          rx[index], ry[index], rz[index],
                          vz[index], vy[index], vz[index],
                          0, 0, 0, X/2, -Y/2, -H, -X/2, -Y/2, -H,
                          2, offset);
        intersectTriangle(ts, pts,
                          rx[index], ry[index], rz[index],
                          vz[index], vy[index], vz[index],
                          0, 0, 0, -X/2, -Y/2, -H, -X/2, Y/2, -H,
                          3, offset);
        intersectTriangle(ts, pts,
                          rx[index], ry[index], rz[index],
                          vz[index], vy[index], vz[index],
                          0, 0, 0, -X/2, Y/2, -H, X/2, Y/2, -H,
                          4, offset);
        __syncthreads();
        //printf("index = %i:\n    ts[%i] = %f ts[%i] = %f ts[%i] = %f ts[%i] = %f ts[%i] = %f\n    rx[%i] = %f ry[%i] = %f rz[%i] = %f\n    vx[%i] = %f vy[%i] = %f vz[%i] = %f\n    pts[%i] = %f pts[%i] = %f pts[%i] = %f\n    pts[%i] = %f pts[%i] = %f pts[%i] = %f\n", index, 5*index, ts[5*index], 5*index+1, ts[5*index+1], 5*index+2, ts[5*index+2], 5*index+3, ts[5*index+3], 5*index+4, ts[5*index+4], index, rx[index], index, ry[index], index, rz[index], index, vx[index], index, vy[index], index, vz[index], 6*index, pts[6*index], 6*index+1, pts[6*index+1], 6*index+2, pts[6*index+2], 6*index+3, pts[6*index+3], 6*index+4, pts[6*index+4], 6*index+5, pts[6*index+5]);
    }
}

__global__ void intersectSphere(float *rx, float *ry, float *rz,
                                float *vx, float *vy, float *vz,
                                const float radius,
                                const int N, float *ts, float *pts)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    // This is done to prevent excess threads from interfering in the code.
    if (index < N)
    {
        /* Calculates the a, b, and c parameters needed for the
         * quadratic formula. These parameters are defined by the
         * equation that is developed by plugging the components
         * of the ray equation for a neutron
         * (<x,y,z> = <x0,y0,z0>+t*<vx,vy,vz>) into the equation of
         * a Sphere.
         */
        float a = dot(vx[index], vy[index], vz[index],
                      vx[index], vy[index], vz[index]);
        float b = 2 * dot(rx[index], ry[index], rz[index],
                          vx[index], vy[index], vz[index]);
        float c = dot(rx[index], ry[index], rz[index],
                      rx[index], ry[index], rz[index]);
        c -= radius*radius;
        /* The solveQuadratic function is used to calculate the
         * two potential intersection times. If the function
         * returns false, the neutron does not intersect, and the
         * corresponding values in ts are set to -1.
         */
        float t0, t1;
        if (!solveQuadratic(a, b, c, t0, t1))
        {
            ts[2*index] = -1;
            ts[2*index + 1] = -1;
            return;
        }
        /* If solveQuadratic returns true, the times are stored in 
         * ts, and the intersection points are calculated and stored
         * in pts.
         */
        else
        {
            if (t0 < 0)
            {
                ts[2*index] = -1;
            }
            else
            {
                ts[2*index] = t0;
                pts[6*index] = rx[index] + vx[index] * t0;
                pts[6*index+1] = ry[index] + vy[index] * t0;
                pts[6*index+2] = rz[index] + vz[index] * t0;
            }
            if (t1 < 0)
            {
                ts[2*index+1] = -1;
            }
            else
            {
                ts[2*index + 1] = t1;
                pts[6*index+3] = rx[index] + vx[index] * t1;
                pts[6*index+4] = ry[index] + vy[index] * t1;
                pts[6*index+5] = rz[index] + vz[index] * t1;
            }
        }
        __syncthreads();
    }
}

__global__ void simplifyTimes(const float *times, const int N, const int groupSize, float *simp)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    // This is done to prevent excess threads from interfering in the code.
    if (index < N)
    {
        int count = 0;
        for (int i = 0; i < groupSize; i++)
        {
            if (times[groupSize * index + i] != -1 && count < 2)
            {
                simp[2*index+count] = times[groupSize*index+i];
                count++;
            }
        }
    }
}

__global__ void prepRand(curandState *state, int seed)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    curand_init(((seed << 10) + idx), 0, 0, &state[idx]); 
}

__device__ void randCoord(float* inters, float* time , float *sx, float *sy, float *sz, curandState *state)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    /* Instead of pasing the initial ray data, the two intersection
     * points and times are used to recalculate the velocities.
     */
    float dt = time[1] - time[0];
    float mx = (inters[3] - inters[0])/dt;
    float my = (inters[4] - inters[1])/dt;
    float mz = (inters[5] - inters[2])/dt;
    // cuRand is used to generate a random time between 0 and dt.
    float randt = curand_uniform(&(state[index]));
    randt *= dt;
    /* Basic kinematics are used to calculate the coordinates of
     * the randomly chosen scattering site.
     */
    *sx = inters[0] + mx*randt;
    *sy = inters[1] + my*randt;
    *sz = inters[2] + mz*randt;
}

__global__ void calcScatteringSites(float* ts, float* int_pts, float* pos, curandState *state, const int N)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    // This is done to prevent excess threads from interfering in the code.
    if (index < N)
    {
        /* If the intersection times for the neutron are the default
         * value of -5, there was no intersection, so the function
         * terminates.
         */
        if (ts[2*index] != -5 && ts[2*index+1] != -5)
        {
            /* The randCoord function assumes that the first time
             * is smaller than the second. If this is not the
             * case, the times and the corresponding intersection
             * coordinates are swapped.
             */
            if (ts[2*index] > ts[2*index+1])
            {
                float tmpt, tmpc;
                tmpt = ts[2*index];
                ts[2*index] = ts[2*index+1];
                ts[2*index+1] = tmpt;
                for (int i = 6*index; i < 6*index+3; i++)
                {
                    tmpc = int_pts[i];
                    int_pts[i] = int_pts[i + 3];
                    int_pts[i + 3] = tmpc;
                }
            }
            /* The randCoord function is called to determine the
             * scattering site.
             */
            randCoord(&(int_pts[6*index]), &(ts[2*index]), &(pos[3*index + 0]), &(pos[3*index + 1]), &(pos[3*index + 2]), state);
        }
    }
}
