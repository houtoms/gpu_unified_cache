#include <iostream>
#include <metrics.h>
using namespace std;
// #define DATA_TYPE float
// #define DATA_TYPE double
#define warpSize 32 

#define IN_1D(_x) in[_x]
#define OUT_1D(_x) out[_x]
#define ARG_1D(_l,_x) args[(_l)*(N)+(_x)]

// #define __DEBUG

#ifdef __DEBUG
#define ITER 1
#else
#define ITER 100
#endif

void Init_Args_1D(DATA_TYPE *args, int l, int N, DATA_TYPE val)
{
    for(int k = 0; k < l; k++)
    {
        for(int i = 0; i < N; i++)
        {
            ARG_1D(k,i) = val; 
        }
    }
}

void Init_Input_1D(DATA_TYPE *in, int n, unsigned int seed)
{
    srand(seed);
    for(int i = 0; i < n; i++)
    {
#ifdef __DEBUG
        IN_1D(i) = 1.0; 
#else
        IN_1D(i) = (DATA_TYPE)rand()*10.0 / ((long)RAND_MAX);
#endif
    }
}

void Clear_Output_1D(DATA_TYPE *in, int n)
{
    for(int i = 0; i < n; i++)
    {
        IN_1D(i) = 0.0;
    }
}

void Show_Me(DATA_TYPE *in, int n, string prompt)
{
    cout << prompt << endl;
    for(int i = 0; i < n; i++)
    {
        std::cout << IN_1D(i) << ",";
    }
    std::cout << std::endl;
}

inline double tol_finder(int error_tol)
{
    double val = 1.0;
    for(; error_tol > 0; error_tol--)
        val *= 10;
    return 1.0/(double)val;
}

bool Verify(DATA_TYPE *test, DATA_TYPE *ref, int n)
{
    bool flag = true;
    double precision = tol_finder(2);

    for(int i = 0; i < n; i++)
    {
        if(fabs(test[i]-ref[i]) > precision)
        {
            std::cout << "wrong at " << i << " test:" << test[i] << " (ref: " << ref[i] << ")";
            std::cout << std::endl;
            flag = false;
            break;
        }
    }
    return flag;
}


void Stencil_Seq(DATA_TYPE *in, DATA_TYPE *out, DATA_TYPE a0, DATA_TYPE a1, DATA_TYPE a2,
        DATA_TYPE a3, DATA_TYPE a4, DATA_TYPE a5, DATA_TYPE a6, int N)
{
    for(int i = 0; i < N; i++)
    {
        int w1 = (i < 1   )    ? 0   : i - 1;
        int e1 = (i >= N-1)    ? N-1 : i + 1;
        int w2 = (i < 2   )    ? 0   : i - 2;
        int e2 = (i >= N-2)    ? N-1 : i + 2;
        int w3 = (i < 3   )    ? 0   : i - 3;
        int e3 = (i >= N-3)    ? N-1 : i + 3;
        OUT_1D(i) = a0*IN_1D(w3) + 
                    a1*IN_1D(w2) + 
                    a2*IN_1D(w1) + 
                    a3*IN_1D(i ) + 
                    a4*IN_1D(e1) + 
                    a5*IN_1D(e2) + 
                    a6*IN_1D(e3) ;
    }
}

__global__ void Stencil_Cuda(DATA_TYPE *in, DATA_TYPE *out, DATA_TYPE a0, DATA_TYPE a1, DATA_TYPE a2,
        DATA_TYPE a3, DATA_TYPE a4, DATA_TYPE a5, DATA_TYPE a6 , int N) 
{
    int i = threadIdx.x + blockIdx.x * blockDim.x ;  
    int w1 = (i < 1   )    ? 0   : i - 1;
    int e1 = (i >= N-1)    ? N-1 : i + 1;
    int w2 = (i < 2   )    ? 0   : i - 2;
    int e2 = (i >= N-2)    ? N-1 : i + 2;
    int w3 = (i < 3   )    ? 0   : i - 3;
    int e3 = (i >= N-3)    ? N-1 : i + 3;
    OUT_1D(i) = a0*IN_1D(w3) + 
                a1*IN_1D(w2) + 
                a2*IN_1D(w1) + 
                a3*IN_1D(i ) + 
                a4*IN_1D(e1) + 
                a5*IN_1D(e2) + 
                a6*IN_1D(e3) ;
}

__global__ void Stencil_Cuda_Sm(DATA_TYPE *in, DATA_TYPE *out, DATA_TYPE a0, DATA_TYPE a1, DATA_TYPE a2,
        DATA_TYPE a3, DATA_TYPE a4, DATA_TYPE a5, DATA_TYPE a6 , int N) 
{
    __shared__ DATA_TYPE local[256+2*3];
    unsigned int tid = threadIdx.x;
    // unsigned int lane_id = tid % warpSize;
    unsigned int gid = threadIdx.x + blockIdx.x * blockDim.x ;  
    int local_id = tid + 3;
    local[local_id] = IN_1D(gid);

    int w1 = (gid < 1   )    ? 0   : gid - 1;
    int e1 = (gid >= N-1)    ? N-1 : gid + 1;
    int w2 = (gid < 2   )    ? 0   : gid - 2;
    int e2 = (gid >= N-2)    ? N-1 : gid + 2;
    int w3 = (gid < 3   )    ? 0   : gid - 3;
    int e3 = (gid >= N-3)    ? N-1 : gid + 3;
    if(tid == 0)
    {
        local[local_id-1] = IN_1D(w1);
        local[local_id-2] = IN_1D(w2);
        local[local_id-3] = IN_1D(w3);
    }
    if(tid == blockDim.x - 1)
    {
        local[local_id+1] = IN_1D(e1);
        local[local_id+2] = IN_1D(e2);
        local[local_id+3] = IN_1D(e3);
    }
    __syncthreads();

    OUT_1D(gid) = a0*local[local_id-3] + 
                  a1*local[local_id-2] + 
                  a2*local[local_id-1] + 
                  a3*local[local_id  ] + 
                  a4*local[local_id+1] + 
                  a5*local[local_id+2] + 
                  a6*local[local_id+3] ;
}

__global__ void Stencil_Cuda_Shfl(DATA_TYPE *in, DATA_TYPE *out, DATA_TYPE a0, DATA_TYPE a1, DATA_TYPE a2,
        DATA_TYPE a3, DATA_TYPE a4, DATA_TYPE a5, DATA_TYPE a6 , int N) 
{
    unsigned int gid = threadIdx.x + blockIdx.x * blockDim.x ;  
    unsigned int tid = threadIdx.x;
    unsigned int lane_id = tid % warpSize;

    int warp_id_x = (threadIdx.x + blockIdx.x * blockDim.x)>>5;

    DATA_TYPE threadInput0, threadInput1;
    int new_i = (warp_id_x<<5) + lane_id%34 -3;
    new_i = (new_i < 0  )  ? 0   : new_i;
    threadInput0 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+32)/34)*34 + (lane_id+32)%34 -3;
    new_i = (new_i < 0  )  ? 0   : new_i;
    new_i = (new_i > N-1)  ? N-1 : new_i;
    threadInput1 = IN_1D(new_i);

    DATA_TYPE sum0 = 0.0;
    int friend_id0;
    DATA_TYPE tx0, ty0;

    friend_id0 = (lane_id+0 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    sum0 += a0*tx0;

    friend_id0 = (lane_id+1 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    sum0 += a1*((lane_id < 31)? tx0: ty0);

    friend_id0 = (lane_id+2 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    sum0 += a2*((lane_id < 30)? tx0: ty0);

    friend_id0 = (lane_id+3 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    sum0 += a3*((lane_id < 29)? tx0: ty0);

    friend_id0 = (lane_id+4 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    sum0 += a4*((lane_id < 28)? tx0: ty0);

    friend_id0 = (lane_id+5 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    sum0 += a5*((lane_id < 27)? tx0: ty0);

    friend_id0 = (lane_id+6 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    sum0 += a6*((lane_id < 26)? tx0: ty0);


    OUT_1D(gid) = sum0; 
}

__global__ void Stencil_Cuda_Shfl2(DATA_TYPE *in, DATA_TYPE *out, DATA_TYPE a0, DATA_TYPE a1, DATA_TYPE a2,
        DATA_TYPE a3, DATA_TYPE a4, DATA_TYPE a5, DATA_TYPE a6 , int N) 
{
    unsigned int tid = threadIdx.x;
    unsigned int lane_id = tid % warpSize;
    unsigned int gid = (((threadIdx.x + blockIdx.x * blockDim.x)>>5)<<6) + lane_id ;  
    int warp_id_x = ((((threadIdx.x + blockIdx.x * blockDim.x)>>5)<<6) + lane_id)>>5;

    DATA_TYPE threadInput0, threadInput1, threadInput2;
    int new_i = (warp_id_x<<5) + lane_id%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput0 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+32)/34)*34 + (lane_id+32)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput1 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+64)/34)*34 + (lane_id+64)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    new_i = (new_i > N-1)    ? N-1 : new_i;
    threadInput2 = IN_1D(new_i);

    DATA_TYPE sum0 = 0.0;
    DATA_TYPE sum1 = 0.0;
    int friend_id0;
    // int friend_id1;
    DATA_TYPE tx0, ty0, tx1, ty1;

    friend_id0 = (lane_id+0 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    sum0 += a0*tx0;
    sum1 += a0*tx1;

    friend_id0 = (lane_id+1 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    sum0 += a1*((lane_id < 31)? tx0: ty0);
    sum1 += a1*((lane_id < 31)? tx1: ty1);

    friend_id0 = (lane_id+2 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    sum0 += a2*((lane_id < 30)? tx0: ty0);
    sum1 += a2*((lane_id < 30)? tx1: ty1);

    friend_id0 = (lane_id+3 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    sum0 += a3*((lane_id < 29)? tx0: ty0);
    sum1 += a3*((lane_id < 29)? tx1: ty1);

    friend_id0 = (lane_id+4 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    sum0 += a4*((lane_id < 28)? tx0: ty0);
    sum1 += a4*((lane_id < 28)? tx1: ty1);

    friend_id0 = (lane_id+5 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    sum0 += a5*((lane_id < 27)? tx0: ty0);
    sum1 += a5*((lane_id < 27)? tx1: ty1);

    friend_id0 = (lane_id+6 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    sum0 += a6*((lane_id < 26)? tx0: ty0);
    sum1 += a6*((lane_id < 26)? tx1: ty1);


    OUT_1D(gid   ) = sum0; 
    OUT_1D(gid+32) = sum1; 
}

__global__ void Stencil_Cuda_Shfl4(DATA_TYPE *in, DATA_TYPE *out, DATA_TYPE a0, DATA_TYPE a1, DATA_TYPE a2,
        DATA_TYPE a3, DATA_TYPE a4, DATA_TYPE a5, DATA_TYPE a6 , int N) 
{
    unsigned int tid = threadIdx.x;
    unsigned int lane_id = tid % warpSize;
    unsigned int gid = (((threadIdx.x + blockIdx.x * blockDim.x)>>5)<<7) + lane_id ;  
    int warp_id_x = ((((threadIdx.x + blockIdx.x * blockDim.x)>>5)<<7) + lane_id)>>5;

    DATA_TYPE threadInput0, threadInput1, threadInput2, threadInput3, threadInput4; 
    int new_i = (warp_id_x<<5) + lane_id%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput0 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+32)/34)*34 + (lane_id+32)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput1 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+64)/34)*34 + (lane_id+64)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput2 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+96)/34)*34 + (lane_id+96)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput3 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+128)/34)*34 + (lane_id+128)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    new_i = (new_i > N-1)    ? N-1 : new_i;
    threadInput4 = IN_1D(new_i);

    DATA_TYPE sum0 = 0.0;
    DATA_TYPE sum1 = 0.0;
    DATA_TYPE sum2 = 0.0;
    DATA_TYPE sum3 = 0.0;
    int friend_id0;
    // int friend_id1;
    DATA_TYPE tx0, ty0, tx1, ty1;
    DATA_TYPE tx2, ty2, tx3, ty3;

    friend_id0 = (lane_id+0 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    sum0 += a0*tx0;
    sum1 += a0*tx1;
    sum2 += a0*tx2;
    sum3 += a0*tx3;

    friend_id0 = (lane_id+1 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    sum0 += a1*((lane_id < 31)? tx0: ty0);
    sum1 += a1*((lane_id < 31)? tx1: ty1);
    sum2 += a1*((lane_id < 31)? tx2: ty2);
    sum3 += a1*((lane_id < 31)? tx3: ty3);

    friend_id0 = (lane_id+2 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    sum0 += a2*((lane_id < 30)? tx0: ty0);
    sum1 += a2*((lane_id < 30)? tx1: ty1);
    sum2 += a2*((lane_id < 30)? tx2: ty2);
    sum3 += a2*((lane_id < 30)? tx3: ty3);

    friend_id0 = (lane_id+3 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    sum0 += a3*((lane_id < 29)? tx0: ty0);
    sum1 += a3*((lane_id < 29)? tx1: ty1);
    sum2 += a3*((lane_id < 29)? tx2: ty2);
    sum3 += a3*((lane_id < 29)? tx3: ty3);

    friend_id0 = (lane_id+4 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    sum0 += a4*((lane_id < 28)? tx0: ty0);
    sum1 += a4*((lane_id < 28)? tx1: ty1);
    sum2 += a4*((lane_id < 28)? tx2: ty2);
    sum3 += a4*((lane_id < 28)? tx3: ty3);

    friend_id0 = (lane_id+5 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    sum0 += a5*((lane_id < 27)? tx0: ty0);
    sum1 += a5*((lane_id < 27)? tx1: ty1);
    sum2 += a5*((lane_id < 27)? tx2: ty2);
    sum3 += a5*((lane_id < 27)? tx3: ty3);

    friend_id0 = (lane_id+6 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    sum0 += a6*((lane_id < 26)? tx0: ty0);
    sum1 += a6*((lane_id < 26)? tx1: ty1);
    sum2 += a6*((lane_id < 26)? tx2: ty2);
    sum3 += a6*((lane_id < 26)? tx3: ty3);


    OUT_1D(gid   ) = sum0; 
    OUT_1D(gid+32) = sum1; 
    OUT_1D(gid+64) = sum2; 
    OUT_1D(gid+96) = sum3; 
}

__global__ void Stencil_Cuda_Shfl8(DATA_TYPE *in, DATA_TYPE *out, DATA_TYPE a0, DATA_TYPE a1, DATA_TYPE a2,
        DATA_TYPE a3, DATA_TYPE a4, DATA_TYPE a5, DATA_TYPE a6 , int N) 
{
    unsigned int tid = threadIdx.x;
    unsigned int lane_id = tid % warpSize;
    unsigned int gid = (((threadIdx.x + blockIdx.x * blockDim.x)>>5)<<8) + lane_id ;  
    int warp_id_x = ((((threadIdx.x + blockIdx.x * blockDim.x)>>5)<<8) + lane_id)>>5;

    DATA_TYPE threadInput0, threadInput1, threadInput2, threadInput3, threadInput4, threadInput5,
              threadInput6, threadInput7, threadInput8;
    int new_i = (warp_id_x<<5) + lane_id%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput0 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+32)/34)*34 + (lane_id+32)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput1 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+64)/34)*34 + (lane_id+64)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput2 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+96)/34)*34 + (lane_id+96)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput3 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+128)/34)*34 + (lane_id+128)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput4 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+160)/34)*34 + (lane_id+160)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput5 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+192)/34)*34 + (lane_id+192)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput6 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+224)/34)*34 + (lane_id+224)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    threadInput7 = IN_1D(new_i);
    new_i = (warp_id_x<<5) + ((lane_id+256)/34)*34 + (lane_id+256)%34 -3;
    new_i = (new_i < 0)   ? 0   : new_i;
    new_i = (new_i > N-1)    ? N-1 : new_i;
    threadInput8 = IN_1D(new_i);

    DATA_TYPE sum0 = 0.0;
    DATA_TYPE sum1 = 0.0;
    DATA_TYPE sum2 = 0.0;
    DATA_TYPE sum3 = 0.0;
    DATA_TYPE sum4 = 0.0;
    DATA_TYPE sum5 = 0.0;
    DATA_TYPE sum6 = 0.0;
    DATA_TYPE sum7 = 0.0;
    int friend_id0;
    // int friend_id1;
    DATA_TYPE tx0, ty0, tx1, ty1;
    DATA_TYPE tx2, ty2, tx3, ty3;
    DATA_TYPE tx4, ty4, tx5, ty5;
    DATA_TYPE tx6, ty6, tx7, ty7;

    friend_id0 = (lane_id+0 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    tx4 = __shfl(threadInput4, friend_id0);
    tx5 = __shfl(threadInput5, friend_id0);
    tx6 = __shfl(threadInput6, friend_id0);
    tx7 = __shfl(threadInput7, friend_id0);
    sum0 += a0*tx0;
    sum1 += a0*tx1;
    sum2 += a0*tx2;
    sum3 += a0*tx3;
    sum4 += a0*tx4;
    sum5 += a0*tx5;
    sum6 += a0*tx6;
    sum7 += a0*tx7;

    friend_id0 = (lane_id+1 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    tx4 = __shfl(threadInput4, friend_id0);
    ty4 = __shfl(threadInput5, friend_id0);
    tx5 = __shfl(threadInput5, friend_id0);
    ty5 = __shfl(threadInput6, friend_id0);
    tx6 = __shfl(threadInput6, friend_id0);
    ty6 = __shfl(threadInput7, friend_id0);
    tx7 = __shfl(threadInput7, friend_id0);
    ty7 = __shfl(threadInput8, friend_id0);
    sum0 += a1*((lane_id < 31)? tx0: ty0);
    sum1 += a1*((lane_id < 31)? tx1: ty1);
    sum2 += a1*((lane_id < 31)? tx2: ty2);
    sum3 += a1*((lane_id < 31)? tx3: ty3);
    sum4 += a1*((lane_id < 31)? tx4: ty4);
    sum5 += a1*((lane_id < 31)? tx5: ty5);
    sum6 += a1*((lane_id < 31)? tx6: ty6);
    sum7 += a1*((lane_id < 31)? tx7: ty7);

    friend_id0 = (lane_id+2 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    tx4 = __shfl(threadInput4, friend_id0);
    ty4 = __shfl(threadInput5, friend_id0);
    tx5 = __shfl(threadInput5, friend_id0);
    ty5 = __shfl(threadInput6, friend_id0);
    tx6 = __shfl(threadInput6, friend_id0);
    ty6 = __shfl(threadInput7, friend_id0);
    tx7 = __shfl(threadInput7, friend_id0);
    ty7 = __shfl(threadInput8, friend_id0);
    sum0 += a2*((lane_id < 30)? tx0: ty0);
    sum1 += a2*((lane_id < 30)? tx1: ty1);
    sum2 += a2*((lane_id < 30)? tx2: ty2);
    sum3 += a2*((lane_id < 30)? tx3: ty3);
    sum4 += a2*((lane_id < 30)? tx4: ty4);
    sum5 += a2*((lane_id < 30)? tx5: ty5);
    sum6 += a2*((lane_id < 30)? tx6: ty6);
    sum7 += a2*((lane_id < 30)? tx7: ty7);

    friend_id0 = (lane_id+3 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    tx4 = __shfl(threadInput4, friend_id0);
    ty4 = __shfl(threadInput5, friend_id0);
    tx5 = __shfl(threadInput5, friend_id0);
    ty5 = __shfl(threadInput6, friend_id0);
    tx6 = __shfl(threadInput6, friend_id0);
    ty6 = __shfl(threadInput7, friend_id0);
    tx7 = __shfl(threadInput7, friend_id0);
    ty7 = __shfl(threadInput8, friend_id0);
    sum0 += a3*((lane_id < 29)? tx0: ty0);
    sum1 += a3*((lane_id < 29)? tx1: ty1);
    sum2 += a3*((lane_id < 29)? tx2: ty2);
    sum3 += a3*((lane_id < 29)? tx3: ty3);
    sum4 += a3*((lane_id < 29)? tx4: ty4);
    sum5 += a3*((lane_id < 29)? tx5: ty5);
    sum6 += a3*((lane_id < 29)? tx6: ty6);
    sum7 += a3*((lane_id < 29)? tx7: ty7);

    friend_id0 = (lane_id+4 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    tx4 = __shfl(threadInput4, friend_id0);
    ty4 = __shfl(threadInput5, friend_id0);
    tx5 = __shfl(threadInput5, friend_id0);
    ty5 = __shfl(threadInput6, friend_id0);
    tx6 = __shfl(threadInput6, friend_id0);
    ty6 = __shfl(threadInput7, friend_id0);
    tx7 = __shfl(threadInput7, friend_id0);
    ty7 = __shfl(threadInput8, friend_id0);
    sum0 += a4*((lane_id < 28)? tx0: ty0);
    sum1 += a4*((lane_id < 28)? tx1: ty1);
    sum2 += a4*((lane_id < 28)? tx2: ty2);
    sum3 += a4*((lane_id < 28)? tx3: ty3);
    sum4 += a4*((lane_id < 28)? tx4: ty4);
    sum5 += a4*((lane_id < 28)? tx5: ty5);
    sum6 += a4*((lane_id < 28)? tx6: ty6);
    sum7 += a4*((lane_id < 28)? tx7: ty7);

    friend_id0 = (lane_id+5 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    tx4 = __shfl(threadInput4, friend_id0);
    ty4 = __shfl(threadInput5, friend_id0);
    tx5 = __shfl(threadInput5, friend_id0);
    ty5 = __shfl(threadInput6, friend_id0);
    tx6 = __shfl(threadInput6, friend_id0);
    ty6 = __shfl(threadInput7, friend_id0);
    tx7 = __shfl(threadInput7, friend_id0);
    ty7 = __shfl(threadInput8, friend_id0);
    sum0 += a5*((lane_id < 27)? tx0: ty0);
    sum1 += a5*((lane_id < 27)? tx1: ty1);
    sum2 += a5*((lane_id < 27)? tx2: ty2);
    sum3 += a5*((lane_id < 27)? tx3: ty3);
    sum4 += a5*((lane_id < 27)? tx4: ty4);
    sum5 += a5*((lane_id < 27)? tx5: ty5);
    sum6 += a5*((lane_id < 27)? tx6: ty6);
    sum7 += a5*((lane_id < 27)? tx7: ty7);

    friend_id0 = (lane_id+6 )&(warpSize-1);
    tx0 = __shfl(threadInput0, friend_id0);
    ty0 = __shfl(threadInput1, friend_id0);
    tx1 = __shfl(threadInput1, friend_id0);
    ty1 = __shfl(threadInput2, friend_id0);
    tx2 = __shfl(threadInput2, friend_id0);
    ty2 = __shfl(threadInput3, friend_id0);
    tx3 = __shfl(threadInput3, friend_id0);
    ty3 = __shfl(threadInput4, friend_id0);
    tx4 = __shfl(threadInput4, friend_id0);
    ty4 = __shfl(threadInput5, friend_id0);
    tx5 = __shfl(threadInput5, friend_id0);
    ty5 = __shfl(threadInput6, friend_id0);
    tx6 = __shfl(threadInput6, friend_id0);
    ty6 = __shfl(threadInput7, friend_id0);
    tx7 = __shfl(threadInput7, friend_id0);
    ty7 = __shfl(threadInput8, friend_id0);
    sum0 += a6*((lane_id < 26)? tx0: ty0);
    sum1 += a6*((lane_id < 26)? tx1: ty1);
    sum2 += a6*((lane_id < 26)? tx2: ty2);
    sum3 += a6*((lane_id < 26)? tx3: ty3);
    sum4 += a6*((lane_id < 26)? tx4: ty4);
    sum5 += a6*((lane_id < 26)? tx5: ty5);
    sum6 += a6*((lane_id < 26)? tx6: ty6);
    sum7 += a6*((lane_id < 26)? tx7: ty7);




    OUT_1D(gid    ) = sum0; 
    OUT_1D(gid+32 ) = sum1; 
    OUT_1D(gid+64 ) = sum2; 
    OUT_1D(gid+96 ) = sum3; 
    OUT_1D(gid+128) = sum4; 
    OUT_1D(gid+160) = sum5; 
    OUT_1D(gid+192) = sum6; 
    OUT_1D(gid+224) = sum7; 
}

int main(int argc, char **argv)
{
#ifdef __DEBUG
    int n = 512;
#else
    int n = 33554432; // 2^25
#endif
    int total = (n);

    const int K = 7;
#ifdef __DEBUG
    DATA_TYPE args[K] = {1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0};
#else
    DATA_TYPE args[K] = {0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14};
#endif

    DATA_TYPE *in = new DATA_TYPE[total];
    DATA_TYPE *out_ref = new DATA_TYPE[total];
    unsigned int seed = time(NULL);
    Init_Input_1D(in, n, seed);

    // Show_Me(in, n, "Input:");
    for(int i=0; i< ITER; i++)
    {
        Stencil_Seq(in, out_ref, args[0], args[1], args[2], args[3], args[4], args[5], 
                args[6], n);
        swap(in, out_ref);
    }
    swap(in, out_ref);
    // Show_Me(out_ref, n, "Output:");

    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    float milliseconds = 0;
    float time_wo_pci;

    DATA_TYPE *in_d;
    DATA_TYPE *out_d;
    DATA_TYPE *out = new DATA_TYPE[total];
    cudaMalloc((void**)&in_d, total*sizeof(DATA_TYPE));
    cudaMalloc((void**)&out_d, total*sizeof(DATA_TYPE));
    
    // Cuda version
    /////////////////////////////////////////////////////////
    Init_Input_1D(in, n, seed);
    Clear_Output_1D(out, n);
    cudaMemcpy(in_d, in, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);
    cudaMemcpy(out_d, out, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);

    dim3 dimGrid((n)/256, 1, 1);
    dim3 dimBlock(256, 1, 1);

    cudaEventRecord(start);
    for(int i=0; i< ITER; i++)
    {
        Stencil_Cuda<<<dimGrid, dimBlock>>>(in_d, out_d, args[0], args[1], args[2], args[3], args[4], args[5], 
                args[6] , n);
        swap(in_d, out_d);
    }
    swap(in_d, out_d);
    cudaEventRecord(stop);
    cudaMemcpy(out, out_d, (total)*sizeof(DATA_TYPE), cudaMemcpyDeviceToHost);
    // Show_Me(out, n,  "Output(Device):");
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&milliseconds, start, stop);
    cout << "Verify Cuda: " << boolalpha << Verify(out, out_ref, total) << endl;
    cout << "Cuda Time: " << milliseconds << endl;
    time_wo_pci = milliseconds * 1.0e-03;
    printf("FLOPS        : %.3f (GFLOPS)\n", GetGFLOPS(1, 1, n, ITER, OPS_1D7, time_wo_pci));
    printf("Throughput   : %.3f (GB/s)\n", GetThroughput(1, 1, 1, n, ITER, time_wo_pci, sizeof(DATA_TYPE)));

    // Cuda Shared Memory version 
    /////////////////////////////////////////////////////////
    Init_Input_1D(in, n, seed);
    Clear_Output_1D(out, n);
    cudaMemcpy(in_d, in, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);
    cudaMemcpy(out_d, out, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);

    dim3 dimGrid1((n)/256, 1, 1);
    dim3 dimBlock1(256, 1, 1);

    cudaEventRecord(start);
    for(int i=0; i< ITER; i++)
    {
        Stencil_Cuda_Sm<<<dimGrid1, dimBlock1>>>(in_d, out_d, args[0], args[1], args[2], args[3], args[4], args[5], 
                args[6] , n);
        swap(in_d, out_d);
    }
    swap(in_d, out_d);
    cudaEventRecord(stop);
    cudaMemcpy(out, out_d, (total)*sizeof(DATA_TYPE), cudaMemcpyDeviceToHost);
    // Show_Me(out, n,  "Output(Device):");
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&milliseconds, start, stop);
    cout << "Verify Cuda_Sm: " << boolalpha << Verify(out, out_ref, total) << endl;
    cout << "Cuda Time: " << milliseconds << endl;
    time_wo_pci = milliseconds * 1.0e-03;
    printf("FLOPS        : %.3f (GFLOPS)\n", GetGFLOPS(1, 1, n, ITER, OPS_1D7, time_wo_pci));
    printf("Throughput   : %.3f (GB/s)\n", GetThroughput(1, 1, 1, n, ITER, time_wo_pci, sizeof(DATA_TYPE)));

    // Cuda Shfl version 
    /////////////////////////////////////////////////////////
    Init_Input_1D(in, n, seed);
    Clear_Output_1D(out, n);
    cudaMemcpy(in_d, in, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);
    cudaMemcpy(out_d, out, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);

    dim3 dimGrid2((n)/256, 1, 1);
    dim3 dimBlock2(256, 1, 1);

    cudaEventRecord(start);
    for(int i=0; i< ITER; i++)
    {
        Stencil_Cuda_Shfl<<<dimGrid2, dimBlock2>>>(in_d, out_d, args[0], args[1], args[2], args[3], args[4], args[5], 
                args[6] , n);
        swap(in_d, out_d);
    }
    swap(in_d, out_d);
    cudaEventRecord(stop);
    cudaMemcpy(out, out_d, (total)*sizeof(DATA_TYPE), cudaMemcpyDeviceToHost);
    // Show_Me(out, n,  "Output(Device):");
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&milliseconds, start, stop);
    cout << "Verify Cuda_Shfl: " << boolalpha << Verify(out, out_ref, total) << endl;
    cout << "Cuda Time: " << milliseconds << endl;
    time_wo_pci = milliseconds * 1.0e-03;
    printf("FLOPS        : %.3f (GFLOPS)\n", GetGFLOPS(1, 1, n, ITER, OPS_1D7, time_wo_pci));
    printf("Throughput   : %.3f (GB/s)\n", GetThroughput(1, 1, 1, n, ITER, time_wo_pci, sizeof(DATA_TYPE)));

    // Cuda Shfl2 version 
    /////////////////////////////////////////////////////////
    Init_Input_1D(in, n, seed);
    Clear_Output_1D(out, n);
    cudaMemcpy(in_d, in, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);
    cudaMemcpy(out_d, out, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);

    dim3 dimGrid3((n)/(256*2), 1, 1);
    dim3 dimBlock3(256, 1, 1);

    cudaEventRecord(start);
    for(int i=0; i< ITER; i++)
    {
        Stencil_Cuda_Shfl2<<<dimGrid3, dimBlock3>>>(in_d, out_d, args[0], args[1], args[2], args[3], args[4], args[5], 
                args[6] , n);
        swap(in_d, out_d);
    }
    swap(in_d, out_d);
    cudaEventRecord(stop);
    cudaMemcpy(out, out_d, (total)*sizeof(DATA_TYPE), cudaMemcpyDeviceToHost);
    // Show_Me(out, n,  "Output(Device):");
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&milliseconds, start, stop);
    cout << "Verify Cuda_Shfl2: " << boolalpha << Verify(out, out_ref, total) << endl;
    cout << "Cuda Time: " << milliseconds << endl;
    time_wo_pci = milliseconds * 1.0e-03;
    printf("FLOPS        : %.3f (GFLOPS)\n", GetGFLOPS(1, 1, n, ITER, OPS_1D7, time_wo_pci));
    printf("Throughput   : %.3f (GB/s)\n", GetThroughput(1, 1, 1, n, ITER, time_wo_pci, sizeof(DATA_TYPE)));

    // Cuda Shfl4 version 
    /////////////////////////////////////////////////////////
    Init_Input_1D(in, n, seed);
    Clear_Output_1D(out, n);
    cudaMemcpy(in_d, in, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);
    cudaMemcpy(out_d, out, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);

    dim3 dimGrid4((n)/(256*4), 1, 1);
    dim3 dimBlock4(256, 1, 1);

    cudaEventRecord(start);
    for(int i=0; i< ITER; i++)
    {
        Stencil_Cuda_Shfl4<<<dimGrid4, dimBlock4>>>(in_d, out_d, args[0], args[1], args[2], args[3], args[4], args[5], 
                args[6] , n);
        swap(in_d, out_d);
    }
    swap(in_d, out_d);
    cudaEventRecord(stop);
    cudaMemcpy(out, out_d, (total)*sizeof(DATA_TYPE), cudaMemcpyDeviceToHost);
    // Show_Me(out, n,  "Output(Device):");
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&milliseconds, start, stop);
    cout << "Verify Cuda_Shfl4: " << boolalpha << Verify(out, out_ref, total) << endl;
    cout << "Cuda Time: " << milliseconds << endl;
    time_wo_pci = milliseconds * 1.0e-03;
    printf("FLOPS        : %.3f (GFLOPS)\n", GetGFLOPS(1, 1, n, ITER, OPS_1D7, time_wo_pci));
    printf("Throughput   : %.3f (GB/s)\n", GetThroughput(1, 1, 1, n, ITER, time_wo_pci, sizeof(DATA_TYPE)));

    // Cuda Shfl8 version 
    /////////////////////////////////////////////////////////
    Init_Input_1D(in, n, seed);
    Clear_Output_1D(out, n);
    cudaMemcpy(in_d, in, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);
    cudaMemcpy(out_d, out, total*sizeof(DATA_TYPE), cudaMemcpyHostToDevice);

    dim3 dimGrid5((n)/(256*8), 1, 1);
    dim3 dimBlock5(256, 1, 1);

    cudaEventRecord(start);
    for(int i=0; i< ITER; i++)
    {
        Stencil_Cuda_Shfl8<<<dimGrid5, dimBlock5>>>(in_d, out_d, args[0], args[1], args[2], args[3], args[4], args[5], 
                args[6] , n);
        swap(in_d, out_d);
    }
    swap(in_d, out_d);
    cudaEventRecord(stop);
    cudaMemcpy(out, out_d, (total)*sizeof(DATA_TYPE), cudaMemcpyDeviceToHost);
    // Show_Me(out, n,  "Output(Device):");
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&milliseconds, start, stop);
    cout << "Verify Cuda_Shfl8: " << boolalpha << Verify(out, out_ref, total) << endl;
    cout << "Cuda Time: " << milliseconds << endl;
    time_wo_pci = milliseconds * 1.0e-03;
    printf("FLOPS        : %.3f (GFLOPS)\n", GetGFLOPS(1, 1, n, ITER, OPS_1D7, time_wo_pci));
    printf("Throughput   : %.3f (GB/s)\n", GetThroughput(1, 1, 1, n, ITER, time_wo_pci, sizeof(DATA_TYPE)));


    cudaFree(in_d);
    cudaFree(out_d);

    delete[] in;
    delete[] out;
    delete[] out_ref;
}

