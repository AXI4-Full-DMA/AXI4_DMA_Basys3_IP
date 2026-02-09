#include <stdio.h>
#include "platform.h"
#include "xparameters.h"
#include "xtmrctr.h"
#include "xil_io.h"
#include "xintc.h"
#include "xil_exception.h"
#include "xil_cache.h"

// =========================================================================
// 1. 하드웨어 설정 및 주소 정의
// =========================================================================
#define DMA_BASE             XPAR_TOP_DMA_0_BASEADDR
#define BRAM_SRC             0xC0000000
#define BRAM_DST             0xC2000000

// Register Offsets
#define REG_START            0x00
#define REG_STATUS           0x04
#define REG_SRC              0x08
#define REG_DST              0x0C
#define REG_LEN              0x10

// Interrupt IDs (In0 ~ In5)
#define INTR_TIMER           0
#define INTR_M00_DONE        1  // m00_axi_txn_done
#define INTR_M00_ERR         2  // m00_axi_error
#define INTR_M01_DONE        3  // m01_axi_txn_done
#define INTR_M01_ERR         4  // m01_axi_error
#define INTR_UART            5

#define TEST_LEN             32768 // 32KB

// =========================================================================
// 2. 전역 변수 및 상태 플래그 (Interrupt Sync)
// =========================================================================
XIntc   Intc;
XTmrCtr Timer;
volatile u8 g_dma_done = 0;
volatile u8 g_dma_err  = 0;

// =========================================================================
// 3. 인터럽트 서비스 루틴 (ISR)
// =========================================================================
void M00_DoneHandler(void *Ref) { 
    g_dma_done |= 0x01; 
}

void M01_DoneHandler(void *Ref) { 
    g_dma_done |= 0x02; 
}

void ErrorHandler(void *Ref) { 
    g_dma_err = 1; 
}

// =========================================================================
// 4. 시스템 초기화 함수
// =========================================================================
int Init_System() {
    // 1. Interrupt Controller 초기화
if (XIntc_Initialize(&Intc, XPAR_XINTC_0_BASEADDR) != XST_SUCCESS) return XST_FAILURE;
   
    // 2. 핸들러 연결 (기존 오타 수정 완료)
    XIntc_Connect(&Intc, INTR_M00_DONE, (XInterruptHandler)M00_DoneHandler, NULL);
    XIntc_Connect(&Intc, INTR_M00_ERR,  (XInterruptHandler)ErrorHandler,  NULL);
    XIntc_Connect(&Intc, INTR_M01_DONE, (XInterruptHandler)M01_DoneHandler, NULL);
    XIntc_Connect(&Intc, INTR_M01_ERR,  (XInterruptHandler)ErrorHandler,  NULL); // 수정한 부분

    // 3. 인터럽트 활성화
    XIntc_Start(&Intc, XIN_REAL_MODE);
    XIntc_Enable(&Intc, INTR_M00_DONE); XIntc_Enable(&Intc, INTR_M00_ERR);
    XIntc_Enable(&Intc, INTR_M01_DONE); XIntc_Enable(&Intc, INTR_M01_ERR);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler)XIntc_InterruptHandler, &Intc);
    Xil_ExceptionEnable();

    // 4. Timer 초기화
    XTmrCtr_Initialize(&Timer, XPAR_AXI_TIMER_0_BASEADDR);
    XTmrCtr_SetOptions(&Timer, 0, XTC_AUTO_RELOAD_OPTION);
    
    return XST_SUCCESS;
}

// =========================================================================
// 5. Main Execution
// =========================================================================
int main() {
    init_platform();
    Init_System();
    
    u32 *src = (u32 *)BRAM_SRC;
    u32 *dst = (u32 *)BRAM_DST;
    u32 start, end, cpu_ticks, dma_ticks;
    
    // 데이터 초기화
    for(int i=0; i<TEST_LEN/4; i++) src[i] = i;

    printf("\r\n=== DMA vs CPU Performance Showdown ===\r\n");

    // =================================================================
    // Round 1: CPU가 직접 옮기기 (Polling/Memcpy)
    // =================================================================
    printf("\r\n[Round 1] CPU Direct Copy (The Hard Worker)\r\n");
    
    // 캐시 플러시 (공정한 대결을 위해)
    Xil_DCacheFlushRange((UINTPTR)src, TEST_LEN);
    Xil_DCacheInvalidateRange((UINTPTR)dst, TEST_LEN);

    XTmrCtr_Reset(&Timer, 0);
    start = XTmrCtr_GetValue(&Timer, 0);
    XTmrCtr_Start(&Timer, 0);

    // CPU가 땀 흘리며 직접 복사
    for(int i = 0; i < (TEST_LEN/4); i++) {
        dst[i] = src[i];
    }

    end = XTmrCtr_GetValue(&Timer, 0);
    cpu_ticks = end - start;
    
    printf(" -> Time Taken: %lu cycles\r\n", cpu_ticks);
    printf(" -> CPU Status: 100%% Busy (Cannot do anything else)\r\n");


    // =================================================================
    // Round 2: DMA에게 시키고 딴짓하기 (Parallelism)
    // =================================================================
    printf("\r\n[Round 2] DMA Transfer (The Smart Boss)\r\n");

    // Destination 초기화 (검증용)
    for(int i=0; i<TEST_LEN/4; i++) dst[i] = 0;
    Xil_DCacheFlushRange((UINTPTR)dst, TEST_LEN);
    
    g_dma_done = 0; // 플래그 초기화

    XTmrCtr_Reset(&Timer, 0);
    start = XTmrCtr_GetValue(&Timer, 0);
    XTmrCtr_Start(&Timer, 0);

    // 1. DMA 발사!
    Xil_Out32(DMA_BASE + REG_SRC, BRAM_SRC);
    Xil_Out32(DMA_BASE + REG_DST, BRAM_DST);
    Xil_Out32(DMA_BASE + REG_LEN, TEST_LEN);
    Xil_Out32(DMA_BASE + REG_START, 0x01);

    // 2. CPU의 "딴짓" (Parallel Work)
    // DMA가 데이터를 옮기는 동안 CPU는 이 루프를 돌며 카운트를 셉니다.
    volatile int other_work_counter = 0;
    while(g_dma_done != 0x03) { // 0x01(Read)과 0x02(Write)가 모두 완료될 때까지
        other_work_counter++; 
    }

    end = XTmrCtr_GetValue(&Timer, 0);
    dma_ticks = end - start;
    u32 speedup_x100 = (cpu_ticks * 100) / dma_ticks;
    
    printf(" -> Time Taken: %lu cycles\r\n", dma_ticks);
    printf(" -> CPU Work  : I counted up to %d while waiting!\r\n", other_work_counter);
    
    // =================================================================
    // Final Verdict
    // =================================================================
    printf("\r\n[Result Analysis]\r\n");
    printf("Speedup Factor: %lu.%02lu x faster\r\n", speedup_x100 / 100, speedup_x100 % 100);
    printf("Efficiency    : CPU did %d operations for free during DMA.\r\n", other_work_counter);

    cleanup_platform();
    return 0;
}