#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>
#include <chrono>
#include <cmath>

#define CUDA_CHECK(call) \
    do { cudaError_t err = call; if (err != cudaSuccess) { fprintf(stderr, "Error: %s\n", cudaGetErrorString(err)); exit(1); } } while(0)

void computePowerCPU(const float* input, float* output, int size, float exponent) {
    for (int i = 0; i < size; ++i) {
        output[i] = powf(input[i], exponent);
    }
}

__global__ void computePowerGPU(const float* input, float* output, int size, float exponent) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < size) {
        output[idx] = powf(input[idx], exponent);
    }
}

void rotateImageCPU(const unsigned char* src, unsigned char* dst, int w, int h) {
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int newIdx = y * w + x;
            int oldIdx = (h - x - 1) * w + y;
            dst[newIdx] = src[oldIdx];
        }
    }
}

__global__ void rotateImageGPU(const unsigned char* src, unsigned char* dst, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x < w && y < h) {
        int newIdx = y * w + x;
        int oldIdx = (h - x - 1) * w + y;
        dst[newIdx] = src[oldIdx];
    }
}

int main() {
    srand(42);

    // Task 1: Power Array
    const int n = 500000;
    const float p = 0.5f;
    float *dataIn, *resultCpu, *resultGpu;
    float *devIn, *devOut;

    dataIn = (float*)malloc(n * sizeof(float));
    resultCpu = (float*)malloc(n * sizeof(float));
    resultGpu = (float*)malloc(n * sizeof(float));

    for (int i = 0; i < n; ++i) {
        dataIn[i] = (float)(rand() % 1000) / 100.0f;
    }
    memset(resultCpu, 0, n * sizeof(float));
    memset(resultGpu, 0, n * sizeof(float));

    CUDA_CHECK(cudaMalloc(&devIn, n * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&devOut, n * sizeof(float)));
    CUDA_CHECK(cudaMemset(devOut, 0, n * sizeof(float)));
    CUDA_CHECK(cudaMemcpy(devIn, dataIn, n * sizeof(float), cudaMemcpyHostToDevice));

    auto start = std::chrono::high_resolution_clock::now();
    computePowerCPU(dataIn, resultCpu, n, p);
    auto end = std::chrono::high_resolution_clock::now();
    double cpuTime = std::chrono::duration<double, std::milli>(end - start).count();

    int blockSize = 256;
    int gridSize = (n + blockSize - 1) / blockSize;
    cudaEvent_t startEvent, stopEvent;
    CUDA_CHECK(cudaEventCreate(&startEvent));
    CUDA_CHECK(cudaEventCreate(&stopEvent));
    CUDA_CHECK(cudaEventRecord(startEvent));
    computePowerGPU<<<gridSize, blockSize>>>(devIn, devOut, n, p);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaEventRecord(stopEvent));
    CUDA_CHECK(cudaEventSynchronize(stopEvent));
    float gpuTime;
    CUDA_CHECK(cudaEventElapsedTime(&gpuTime, startEvent, stopEvent));

    CUDA_CHECK(cudaMemcpy(resultGpu, devOut, n * sizeof(float), cudaMemcpyDeviceToHost));

    bool task1Match = true;
    for (int i = 0; i < n; ++i) {
        if (fabs(resultCpu[i] - resultGpu[i]) > 1e-5) {
            task1Match = false;
            break;
        }
    }

    printf("Task 1: Power Array\nCPU Time: %.2f ms\nGPU Time: %.2f ms\nResults match: %s\nSample: A[0]=%.2f, B_cpu[0]=%.2f, B_gpu[0]=%.2f\n",
           cpuTime, gpuTime, task1Match ? "Yes" : "No", dataIn[0], resultCpu[0], resultGpu[0]);

    free(dataIn);
    free(resultCpu);
    free(resultGpu);
    CUDA_CHECK(cudaFree(devIn));
    CUDA_CHECK(cudaFree(devOut));
    CUDA_CHECK(cudaEventDestroy(startEvent));
    CUDA_CHECK(cudaEventDestroy(stopEvent));

    // Task 2: Rotate Image
    const int w = 512;
    const int h = 512;
    unsigned char *imgIn, *imgOutCpu, *imgOutGpu;
    unsigned char *devImgIn, *devImgOut;

    imgIn = (unsigned char*)malloc(w * h * sizeof(unsigned char));
    imgOutCpu = (unsigned char*)malloc(w * h * sizeof(unsigned char));
    imgOutGpu = (unsigned char*)malloc(w * h * sizeof(unsigned char));

    for (int i = 0; i < w * h; ++i) {
        imgIn[i] = (unsigned char)(rand() % 256);
    }
    memset(imgOutCpu, 0, w * h * sizeof(unsigned char));
    memset(imgOutGpu, 0, w * h * sizeof(unsigned char));

    CUDA_CHECK(cudaMalloc(&devImgIn, w * h * sizeof(unsigned char)));
    CUDA_CHECK(cudaMalloc(&devImgOut, w * h * sizeof(unsigned char)));
    CUDA_CHECK(cudaMemset(devImgOut, 0, w * h * sizeof(unsigned char)));
    CUDA_CHECK(cudaMemcpy(devImgIn, imgIn, w * h * sizeof(unsigned char), cudaMemcpyHostToDevice));

    start = std::chrono::high_resolution_clock::now();
    rotateImageCPU(imgIn, imgOutCpu, w, h);
    end = std::chrono::high_resolution_clock::now();
    cpuTime = std::chrono::duration<double, std::milli>(end - start).count();

    dim3 blockDim(16, 16);
    dim3 gridDim((w + blockDim.x - 1) / blockDim.x, (h + blockDim.y - 1) / blockDim.y);
    CUDA_CHECK(cudaEventCreate(&startEvent));
    CUDA_CHECK(cudaEventCreate(&stopEvent));
    CUDA_CHECK(cudaEventRecord(startEvent));
    rotateImageGPU<<<gridDim, blockDim>>>(devImgIn, devImgOut, w, h);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaEventRecord(stopEvent));
    CUDA_CHECK(cudaEventSynchronize(stopEvent));
    CUDA_CHECK(cudaEventElapsedTime(&gpuTime, startEvent, stopEvent));

    CUDA_CHECK(cudaMemcpy(imgOutGpu, devImgOut, w * h * sizeof(unsigned char), cudaMemcpyDeviceToHost));

    bool task2Match = true;
    for (int i = 0; i < w * h; ++i) {
        if (imgOutCpu[i] != imgOutGpu[i]) {
            task2Match = false;
            break;
        }
    }

    printf("\nTask 2: Rotate Image\nCPU Time: %.2f ms\nGPU Time: %.2f ms\nResults match: %s\nSample: input[0]=%u, output_cpu[0]=%u, output_gpu[0]=%u\n",
           cpuTime, gpuTime, task2Match ? "Yes" : "No", imgIn[0], imgOutCpu[0], imgOutGpu[0]);

    free(imgIn);
    free(imgOutCpu);
    free(imgOutGpu);
    CUDA_CHECK(cudaFree(devImgIn));
    CUDA_CHECK(cudaFree(devImgOut));
    CUDA_CHECK(cudaEventDestroy(startEvent));
    CUDA_CHECK(cudaEventDestroy(stopEvent));

    return 0;
}
