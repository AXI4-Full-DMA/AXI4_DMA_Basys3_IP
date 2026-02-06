#include "xparameters.h"
#include "xtmrctr.h"  // AXI Timer 라이브러리
#include "xil_io.h"
#include <stdio.h>

// 타이머 및 DMA 주소 정의
#define TIMER_DEVICE_ID  XPAR_AXI_TIMER_0_BASEADDR
#define DMA_BASE_ADDR    XPAR_TOP_DMA_0_BASEADDR 

XTmrCtr TimerCounter; // 타이머 구조체

int main() {
    uint32_t start_count, end_count, total_count;
    uint32_t transfer_bytes = 1024 * 64; // 테스트용 64KB
    double elapsed_time, throughput;

    // 1. 타이머 초기화
    XTmrCtr_Initialize(&TimerCounter, TIMER_DEVICE_ID);
    XTmrCtr_SetOptions(&TimerCounter, 0, XTC_AUTO_RELOAD_OPTION);

    printf("--- Basys3 DMA Performance Test ---\n");

    // 2. 타이머 시작 전 카운트 기록
    XTmrCtr_Start(&TimerCounter, 0);
    start_count = XTmrCtr_GetValue(&TimerCounter, 0);

    // 3. DMA 동작 시작 (기존 코드와 동일)
    Xil_Out32(DMA_BASE_ADDR + 0x10, transfer_bytes); // Length 설정
    Xil_Out32(DMA_BASE_ADDR + 0x00, 0x01);           // Start!

    // 4. 완료 대기 (Polling)
    while ((Xil_In32(DMA_BASE_ADDR + 0x04) & 0x01) == 0);

    // 5. 타이머 종료 후 카운트 기록
    end_count = XTmrCtr_GetValue(&TimerCounter, 0);
    XTmrCtr_Stop(&TimerCounter, 0);

    // 6. 결과 계산 (정수 위주)
    total_count = end_count - start_count;

    // 64비트 정수를 사용하여 오버플로우 방지
    unsigned long long total_count_ll = (unsigned long long)total_count;
    unsigned long long freq_ll = (unsigned long long)XPAR_AXI_TIMER_0_CLOCK_FREQUENCY;

    // 마이크로초 계산
    uint32_t micro_sec = (uint32_t)((total_count_ll * 1000000) / freq_ll);

    // 속도 계산 (KB/s 단위로 먼저 계산)
    uint32_t throughput_mbps = (uint32_t)(( (unsigned long long)transfer_bytes * 1000000 ) / ( (unsigned long long)micro_sec * 1024 * 1024 ));

    printf("Total Clock Cycles: %lu\n", total_count);
    printf("Actual Elapsed Time: %lu us\n", micro_sec);
    printf("Actual Throughput: %lu MB/s\n", throughput_mbps);

    return 0;
}