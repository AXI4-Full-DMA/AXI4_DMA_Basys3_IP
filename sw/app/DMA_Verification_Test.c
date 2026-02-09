/**
 * ============================================================================
 * [Project] AXI4 DMA Functional Verification Suite
 * [Target ] Xilinx FPGA (Basys3)
 * [Goal   ] Verify Data Integrity under Stress Conditions (Boundary, Size, Pattern)
 * [Note   ] Speed measurement is excluded. Focus is on reliability.
 * ============================================================================
 */

#include <stdio.h>
#include "platform.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xil_types.h"
#include "xil_cache.h"

// ============================================================================
// [1] 시스템 주소 설정
// ============================================================================
#define DMA_CTRL_BASE_ADDR   XPAR_TOP_DMA_0_BASEADDR
#define BRAM_READ_ADDR       0xC0000000
#define BRAM_WRITE_ADDR      0xC2000000

// DMA 레지스터 오프셋
#define REG_CTRL_START       0x00
#define REG_STAT_DONE        0x04
#define REG_SRC_ADDR         0x08
#define REG_DST_ADDR         0x0C
#define REG_TRF_LEN          0x10

// 테스트 패턴 모드
#define PATTERN_INCR         0  // 0, 1, 2...
#define PATTERN_WALK_1       1  // 1, 2, 4, 8...
#define PATTERN_INV          2  // 0xFFFFFFFF, 0xFFFFFFFE...

// ============================================================================
// [Helper] 패턴 생성 함수
// ============================================================================
u32 generate_pattern(int mode, int index) {
    switch(mode) {
        case PATTERN_INCR:   return 0x55AA0000 + index;
        case PATTERN_WALK_1: return (1 << (index % 32));
        case PATTERN_INV:    return ~(0x55AA0000 + index);
        default:             return 0x00000000;
    }
}

// ============================================================================
// [Core] 단일 테스트 실행 함수
// ============================================================================
// [Core] 단일 테스트 실행 함수 (Universal Delay 적용 - 멈춤 없음)
int run_test(u32 length, u32 src_offset, u32 dst_offset, int pattern_mode, char* test_name) {
    
    u32 *src_ptr = (u32 *)(UINTPTR)(BRAM_READ_ADDR + src_offset);
    u32 *dst_ptr = (u32 *)(UINTPTR)(BRAM_WRITE_ADDR + dst_offset);
    
    u32 error_cnt = 0;
    u32 num_words = length / 4;

    // 1. 데이터 초기화
    for(int i = 0; i < num_words; i++) {
        src_ptr[i] = generate_pattern(pattern_mode, i);
        dst_ptr[i] = 0xDEADBEEF; 
    }
    
    Xil_DCacheFlushRange((UINTPTR)src_ptr, length);
    Xil_DCacheFlushRange((UINTPTR)dst_ptr, length);

    // 2. 레지스터 설정
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_SRC_ADDR, (u32)(UINTPTR)src_ptr);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_DST_ADDR, (u32)(UINTPTR)dst_ptr);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_TRF_LEN,  length);

    // 3. DMA 트리거
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x00); // Reset
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x01); // Trigger

    // --------------------------------------------------------------------
    // Universal Delay Strategy (만능 딜레이)
    // --------------------------------------------------------------------
    // 조건을 따지지 않고 무조건 CPU를 잠깐 멈춥니다.
    // - 하드웨어가 Start를 인식하고 Done을 0으로 내릴 시간을 줍니다.
    // - 전송이 매우 빠르다면 이 시간 안에 끝나서 Done이 다시 1이 됩니다.
    // - 전송이 느리다면 아직 Done은 0인 상태입니다.
    // 결론: 이 딜레이 후에는 바로 Done=1을 기다려도 안전합니다.
    for(volatile int k = 0; k < 1000; k++); 

    // 4. 완료 대기 (Done = 1이 될 때까지)
    // 이미 끝났다면(Done=1) 즉시 통과, 아직이면(Done=0) 대기.
    while(!(Xil_In32(DMA_CTRL_BASE_ADDR + REG_STAT_DONE) & 0x01));

    // Cleanup
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x00);
    Xil_DCacheInvalidateRange((UINTPTR)dst_ptr, length);

    // 5. 데이터 검증
    for(int i = 0; i < num_words; i++) {
        if(src_ptr[i] != dst_ptr[i]) {
            if(error_cnt == 0) { 
                printf("   [FAIL] %s | Offset: %d | Exp: 0x%08X != Got: 0x%08X\r\n", 
                       test_name, i*4, (unsigned int)src_ptr[i], (unsigned int)dst_ptr[i]);
            }
            error_cnt++;
        }
    }

    // 6. 결과 출력
    if(error_cnt == 0) {
        printf(" [PASS] %-22s | Size: %5d Bytes\r\n", test_name, (int)length);
        return 1; 
    } else {
        printf(" [FAIL] %-22s | Size: %5d Bytes | Errors: %lu\r\n", test_name, (int)length, error_cnt);
        return 0; 
    }
}

// ============================================================================
// [Main] 전체 테스트 시나리오
// ============================================================================
int main() {
    init_platform();
    
    printf("\r\n=======================================================\r\n");
    printf("   AXI4 DMA FUNCTIONAL VERIFICATION SUITE\r\n");
    printf("   (Focus: Integrity, Boundary, Pattern)\r\n");
    printf("=======================================================\r\n");
    
    int total_pass = 0;
    int total_tests = 0;

    // -----------------------------------------------------------------
    // A. Sweep Test (크기 변화 테스트)
    // -----------------------------------------------------------------
    printf("\r\n>>> TEST A: Sweep Test (Various Sizes)\r\n");
    // 4바이트(최소)부터 16KB(대용량)까지 2배씩 늘려가며 테스트
    for(int len = 4; len <= 16384; len *= 2) {
        total_tests++;
        if(run_test(len, 0, 0, PATTERN_INCR, "Size_Sweep")) total_pass++;
    }

    // -----------------------------------------------------------------
    // B. Pattern Test (데이터 패턴 테스트)
    // -----------------------------------------------------------------
    printf("\r\n>>> TEST B: Pattern Test (Data Integrity)\r\n");
    
    total_tests++;
    // Walking 1s: 비트 간 간섭(Short) 확인 (1, 2, 4, 8...)
    if(run_test(4096, 0, 0, PATTERN_WALK_1, "Pattern_Walking1")) total_pass++;

    total_tests++;
    // Inverted: 전원 노이즈 등 확인 (0xFFFFFFFF...)
    if(run_test(4096, 0, 0, PATTERN_INV, "Pattern_Inverted")) total_pass++;

    // -----------------------------------------------------------------
    // C. Boundary Test (경계 조건 테스트) - 가장 중요!
    // -----------------------------------------------------------------
    printf("\r\n>>> TEST C: Boundary Test (4KB Crossing)\r\n");
    
    // Case 1: Source와 Destination 모두 4KB 경계를 가로지름
    // 0xFF0 (4080)번지부터 256바이트 전송 -> 0x1000 (4096)번지 경계 통과
    total_tests++;
    if(run_test(256, 0xFF0, 0xFF0, PATTERN_INCR, "Boundary_Both")) total_pass++;

    // Case 2: Source만 경계 가로지름 (비정렬 테스트)
    total_tests++;
    if(run_test(256, 0xFF0, 0x000, PATTERN_INCR, "Boundary_SrcOnly")) total_pass++;

    // Case 3: Destination만 경계 가로지름
    total_tests++;
    if(run_test(256, 0x000, 0xFF0, PATTERN_INCR, "Boundary_DstOnly")) total_pass++;


    // -----------------------------------------------------------------
    // Final Report
    // -----------------------------------------------------------------
    printf("\r\n=======================================================\r\n");
    printf(" FINAL RESULT: %d / %d Tests Passed\r\n", total_pass, total_tests);
    
    if(total_pass == total_tests) {
        printf(" SUMMARY: System is Functionally PERFECT.\r\n");
    } else {
        printf(" SUMMARY: Setup needs debugging. Check Logic Analyzer.\r\n");
    }
    printf("=======================================================\r\n");

    cleanup_platform();
    return 0;
}