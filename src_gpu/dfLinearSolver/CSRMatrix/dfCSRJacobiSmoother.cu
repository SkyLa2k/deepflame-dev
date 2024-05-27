#include "dfCSRSmoother.H"
#include "dfSolverOpBase.H"

__global__ void csrJacobiSmooth
(
    int nCells,
    double* psi,
    double* psiCopyPtr,
    double* source,
    double* off_diag_value_Ptr,
    int* off_diag_rowptr_Ptr, 
    int* off_diag_colidx_Ptr,
    double* diagPtr
)
{
    int index = blockDim.x * blockIdx.x + threadIdx.x;
    if (index >= nCells)
        return;
    
    double sum = source[index];
    for(int r = off_diag_rowptr_Ptr[index]; r < off_diag_rowptr_Ptr[index + 1]; r++){
        sum -= off_diag_value_Ptr[r] * psiCopyPtr[off_diag_colidx_Ptr[r]];
    }
    psi[index] = sum / diagPtr[index];
}

void CSRJacobiSmoother::smooth
(
    cudaStream_t stream,
    int nSweeps,
    int nCells,
    double* psi,
    double* source,
    double* off_diag_value_Ptr,
    int* off_diag_rowptr_Ptr, 
    int* off_diag_colidx_Ptr,
    double* diagPtr,
    // PARALLEL_
    const dfMatrixDataBase& dataBase,
    double* scalarSendBufList_, 
    double* scalarRecvBufList_,
    double** interfaceBouCoeffs,
    int** faceCells, std::vector<int> nPatchFaces
)
{
    size_t threads_per_block = 1024;
    size_t blocks_per_grid = (nCells + threads_per_block - 1) / threads_per_block;
    
    double* bPrime;
    cudaMalloc(&bPrime, nCells * sizeof(double));

    for (int sweep=0; sweep<nSweeps; sweep++)
    {
        cudaMemcpyAsync(bPrime, source, nCells * sizeof(double), cudaMemcpyDeviceToDevice, stream);

        // // for debug start
        // checkCudaErrors(cudaStreamSynchronize(stream));
        // double source_sum = 0.0;
        // double* test_result;
        // cudaMalloc(&test_result, sizeof(double));
        // reduce(nCells, threads_per_block, blocks_per_grid, bPrime, test_result, dataBase.stream, false);
        // #ifndef PARALLEL_
        //     cudaMemcpyAsync(&source_sum, &test_result[0] , sizeof(double), cudaMemcpyDeviceToHost, dataBase.stream);
        // #else
        //     ncclAllReduce(&test_result[0], &test_result[0], 1, ncclDouble, ncclSum, dataBase.nccl_comm, dataBase.stream);
        //     cudaStreamSynchronize(dataBase.stream);
        //     cudaMemcpyAsync(&source_sum, &test_result[0], sizeof(double), cudaMemcpyDeviceToHost, dataBase.stream);
        // #endif
        // std::cout << nCells << " **gpu source_sum in smooth before: " << source_sum << std::endl;
        // // for debug end

#ifdef PARALLEL_   
        // sign = -1 for negate()
        // --- initMatrixInterfaces & updateMatrixInterfaces ---
        updateMatrixInterfaceCoeffs(
            dataBase.stream, dataBase.neighbProcNo, dataBase.nccl_comm,
            nPatchFaces, psi, bPrime, 
            scalarSendBufList_, scalarRecvBufList_,
            interfaceBouCoeffs, faceCells, -1.0);
#endif
        // // for debug start
        // reduce(nCells, threads_per_block, blocks_per_grid, bPrime, test_result, dataBase.stream, false);
        // #ifndef PARALLEL_
        //     cudaMemcpyAsync(&source_sum, &test_result[0] , sizeof(double), cudaMemcpyDeviceToHost, dataBase.stream);
        // #else
        //     ncclAllReduce(&test_result[0], &test_result[0], 1, ncclDouble, ncclSum, dataBase.nccl_comm, dataBase.stream);
        //     cudaStreamSynchronize(dataBase.stream);
        //     cudaMemcpyAsync(&source_sum, &test_result[0], sizeof(double), cudaMemcpyDeviceToHost, dataBase.stream);
        // #endif
        // std::cout << nCells << " **gpu source_sum in smooth: " << source_sum << std::endl;
        // // for debug end

        double* psiCopyPtr;
        cudaMalloc(&psiCopyPtr, nCells * sizeof(double));
        cudaMemcpyAsync(psiCopyPtr, psi, nCells * sizeof(double), cudaMemcpyDeviceToDevice, stream);
    
        csrJacobiSmooth<<<blocks_per_grid, threads_per_block, 0, stream>>>
            (nCells, psi, psiCopyPtr, bPrime, off_diag_value_Ptr, off_diag_rowptr_Ptr, off_diag_colidx_Ptr, diagPtr);
        checkCudaErrors(cudaStreamSynchronize(stream));

        // // for debug start
        // reduce(nCells, threads_per_block, blocks_per_grid, psi, test_result, dataBase.stream, false);
        // #ifndef PARALLEL_
        //     cudaMemcpyAsync(&source_sum, &test_result[0] , sizeof(double), cudaMemcpyDeviceToHost, dataBase.stream);
        // #else
        //     ncclAllReduce(&test_result[0], &test_result[0], 1, ncclDouble, ncclSum, dataBase.nccl_comm, dataBase.stream);
        //     cudaStreamSynchronize(dataBase.stream);
        //     cudaMemcpyAsync(&source_sum, &test_result[0], sizeof(double), cudaMemcpyDeviceToHost, dataBase.stream);
        // #endif
        // std::cout << nCells << " **gpu source_sum psi: " << source_sum << std::endl;
        // // for debug end
    }
};