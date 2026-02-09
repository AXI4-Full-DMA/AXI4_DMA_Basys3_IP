#include <stdio.h>
#include "platform.h"
#include "xparameters.h"
#include "xtmrctr.h"    // AXI Timer 라이브러리
#include "xil_io.h"     // 레지스터 I/O 함수
#include "xil_types.h"

// =========================================================================
// 하드웨어 주소 및 파라미터 설정
// =========================================================================
// Vivado의 Address Editor에서 확인한 실제 주소값으로 수정하세요.
#define DMA_CTRL_BASE_ADDR   XPAR_TOP_DMA_0_BASEADDR
#define BRAM_READ_ADDR       0xC0000000   // Source BRAM
#define BRAM_WRITE_ADDR      0xC2000000   // Destination BRAM

// 타이머 설정
#define TIMER_DEVICE_ID      XPAR_AXI_TIMER_0_BASEADDR
#define TIMER_FREQ_HZ        XPAR_AXI_TIMER_0_CLOCK_FREQUENCY

// DMA 레지스터 오프셋
#define REG_CTRL_START       0x00
#define REG_STAT_DONE        0x04
#define REG_SRC_ADDR         0x08
#define REG_DST_ADDR         0x0C
#define REG_TRF_LEN          0x10

// 테스트 파라미터 (32KB 전체 전송)
#define TEST_DATA_LEN        32768 

XTmrCtr TimerCounter;

int main() {
    init_platform();

    u32 start_tick, end_tick, total_ticks;
    u32 error_cnt = 0;
    u32 *src_ptr = (u32 *)BRAM_READ_ADDR;
    u32 *dst_ptr = (u32 *)BRAM_WRITE_ADDR;

    // 타이머 초기화
    XTmrCtr_Initialize(&TimerCounter, TIMER_DEVICE_ID);
    XTmrCtr_SetOptions(&TimerCounter, 0, XTC_AUTO_RELOAD_OPTION);

    printf("\r\n--- Basys3 DMA Full Integrated Test ---\r\n");

    // 데이터 초기화 (Source 패턴 입력 및 Destination 클리어)
    printf("Step 1: Initializing BRAMs...\r\n");
    for(int i = 0; i < (TEST_DATA_LEN/4); i++) {
        src_ptr[i] = 0x55AA0000 + i;
        dst_ptr[i] = 0x00000000;
    }

    // DMA 레지스터 설정
    printf("Step 2: Configuring DMA Registers...\r\n");
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_SRC_ADDR, BRAM_READ_ADDR);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_DST_ADDR, BRAM_WRITE_ADDR);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_TRF_LEN,  TEST_DATA_LEN);

    // 측정 시작 및 DMA 트리거
    printf("Step 3: DMA Start & Timing...\r\n");
    XTmrCtr_Start(&TimerCounter, 0);
    start_tick = XTmrCtr_GetValue(&TimerCounter, 0);

    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x01); // Trigger!

    // 이 줄이 없으면 두 번째 실행부터 124 Ticks가 나올 수 있음
    while( (Xil_In32(DMA_CTRL_BASE_ADDR + REG_STAT_DONE) & 0x01) == 1 );

    // 완료 대기 (Polling)
    // 데이터가 목적지에 완벽하게 안착했음: slv_reg1[0]에 1 적힘
    while(!(Xil_In32(DMA_CTRL_BASE_ADDR + REG_STAT_DONE) & 0x01));

    end_tick = XTmrCtr_GetValue(&TimerCounter, 0);
    XTmrCtr_Stop(&TimerCounter, 0);
    printf("Step 4: Hardware Done Received!\r\n");

    // 데이터 정합성 검증
    printf("Step 5: Verifying Data Integrity...\r\n");
    for(int i = 0; i < (TEST_DATA_LEN/4); i++) {
        if(src_ptr[i] != dst_ptr[i]) {
            if(error_cnt < 5) {
                printf("   [Error] Offset %d: Expected 0x%08X, Got 0x%08X\r\n", 
                        i*4, (unsigned int)src_ptr[i], (unsigned int)dst_ptr[i]);
            }
            error_cnt++;
        }
    }

    // 최종 결과 및 성능 계산
    if(error_cnt == 0) {
        printf(">>> SUCCESS: Data matched perfectly!\r\n");

        total_ticks = end_tick - start_tick;
        
        // 64비트 계산으로 오버플로우 방지
        unsigned long long total_ticks_ll = (unsigned long long)total_ticks;
        unsigned long long freq_ll = (unsigned long long)TIMER_FREQ_HZ;
        unsigned long long bytes_ll = (unsigned long long)TEST_DATA_LEN;

        u32 micro_sec = (u32)((total_ticks_ll * 1000000) / freq_ll);
        u32 throughput = (u32)((bytes_ll * 1000000) / ((unsigned long long)micro_sec * 1024 * 1024));

        printf("\r\n[ Performance Report ]\r\n");
        printf("Total Ticks: %lu cycles\r\n", total_ticks);
        printf("Elapsed Time: %lu us\r\n", micro_sec);
        printf("Throughput: %lu MB/s\r\n", throughput);
    } else {
        printf(">>> FAILURE: Total %lu errors found.\r\n", error_cnt);
    }

    printf("--- Test Finished ---\r\n");

    cleanup_platform();
    return 0;
}
