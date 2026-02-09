#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"           // 레지스터 I/O 함수 (Xil_In32, Xil_Out32)
#include "xparameters.h"      // 하드웨어 주소 정보

// =========================================================================
// [1] 하드웨어 주소 및 파라미터 설정 (수정 필요)
// =========================================================================
// Vivado의 Address Editor에서 확인한 실제 주소값으로 수정하세요.
#define DMA_CTRL_BASE_ADDR   XPAR_TOP_DMA_0_BASEADDR         // DMA IP 주소
#define BRAM_READ_ADDR       0xC0000000                      // 소스 BRAM (32KB)
#define BRAM_WRITE_ADDR      0xC2000000                      // 목적지 BRAM (32KB)

// BRAM 크기 정의 (32KB = 32768 Bytes)
#define BRAM_SIZE_BYTES      32768
#define TEST_DATA_LEN        4096   // 테스트할 데이터 크기 (바이트 단위)

// =========================================================================
// [2] DMA 레지스터 오프셋 정의 (Slave 모듈 설계 반영)
// =========================================================================
#define REG_CTRL_START       0x00    // slv_reg0: [0] bit = Start
#define REG_STAT_DONE        0x04    // slv_reg1: [0] bit = Done
#define REG_SRC_ADDR         0x08    // slv_reg2: Source Address
#define REG_DST_ADDR         0x0C    // slv_reg3: Destination Address
#define REG_TRF_LEN          0x10    // slv_reg4: Transfer Length

int main()
{
    init_platform();

    xil_printf("\r\n--- Custom DMA IP BRAM-to-BRAM Test ---\r\n");

    // 포인터 캐스팅 (메모리 직접 접근용)
    u32 *src_bram = (u32 *)BRAM_READ_ADDR;
    u32 *dst_bram = (u32 *)BRAM_WRITE_ADDR;

    // =========================================================================
    // [3] 테스트 데이터 초기화 (추가 가능)
    // =========================================================================
    xil_printf("1. Initializing Source BRAM with pattern data...\r\n");
    for(int i = 0; i < (TEST_DATA_LEN/4); i++) {
        src_bram[i] = 0x55AA0000 + i; // 확인 가능한 특정 패턴 입력
        dst_bram[i] = 0x00000000;      // 목적지는 0으로 초기화
    }

    // =========================================================================
    // [4] DMA 레지스터 설정 (핵심 동작)
    // =========================================================================
    xil_printf("2. Setting DMA Registers...\r\n");

    xil_printf("2-1. Writing Source Address...\r\n");
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_SRC_ADDR, BRAM_READ_ADDR);

    xil_printf("2-2. Writing Destination Address...\r\n");
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_DST_ADDR, BRAM_WRITE_ADDR);

    xil_printf("2-3. Writing Length...\r\n");
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_TRF_LEN, TEST_DATA_LEN);

    // DMA 시작 트리거 (slv_reg0[0] = 1)
    xil_printf("3. Triggering DMA Start!\r\n");
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x01);

    // =========================================================================
    // [5] DMA 완료 대기 (Polling)
    // =========================================================================
    xil_printf("4. Waiting for Hardware Done Signal...\r\n");
    u32 status = 0;
    while(1) {
        status = Xil_In32(DMA_CTRL_BASE_ADDR + REG_STAT_DONE);
        if((status & 0x01) == 1) { // slv_reg1[0] 비트 확인
            break;
        }
        // 무한 루프 방지를 위해 일정 시간 후 타임아웃 로직을 추가할 수 있습니다.
    }
    xil_printf("5. Hardware Signal Received: DMA DONE!\r\n");

    // =========================================================================
    // [6] 데이터 검증 및 결과 보고
    // =========================================================================
    xil_printf("6. Verifying Data...\r\n");
    int error_cnt = 0;
    for(int i = 0; i < (TEST_DATA_LEN/4); i++) {
        if(src_bram[i] != dst_bram[i]) {
            xil_printf("   [Error] Offset %d: Src(0x%08X) != Dst(0x%08X)\r\n", 
                        i*4, src_bram[i], dst_bram[i]);
            error_cnt++;
        }
    }

    if(error_cnt == 0) {
        xil_printf(">>> SUCCESS: DMA Transfer matched perfectly!\r\n");
    } else {
        xil_printf(">>> FAILURE: Total %d data mismatches found.\r\n", error_cnt);
    }

    xil_printf("--- Test Finished ---\r\n");

    cleanup_platform();
    return 0;
}