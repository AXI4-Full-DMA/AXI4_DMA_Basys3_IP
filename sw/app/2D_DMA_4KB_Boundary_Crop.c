#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"       
#include "xparameters.h"  
#include "image_data_ball_60.h" // 60x60 또는 80x80 공 데이터 헤더 (IMG_WIDTH/HEIGHT 정의됨)

// [1] 시스템 주소 맵 설정
#define DMA_CTRL_BASE_ADDR   XPAR_TOP_DMA_2D_0_BASEADDR // 2D DMA 제어용 레지스터 기지 주소
#define BRAM_READ_ADDR       0xC0000000                 // 원본 이미지가 로드될 소스 BRAM
#define BRAM_WRITE_ADDR      0xC2000000                 // 크롭 결과가 저장될 목적지 BRAM

// [2] DMA 레지스터 오프셋 정의
#define REG_CTRL_START       0x00  // [W] 1: Start
#define REG_STAT_DONE        0x04  // [R] 1: Done
#define REG_SRC_ADDR         0x08  // [W] Source Start Address
#define REG_DST_ADDR         0x0C  // [W] Destination Start Address
#define REG_IMG_WIDTH        0x10  // [W] Transfer Width (Bytes)
#define REG_IMG_HEIGHT       0x14  // [W] Transfer Height (Rows)
#define REG_IMG_STRIDE       0x18  // [W] Source Stride (Bytes)

int main() {
    init_platform();
    xil_printf("\r\n--- 2D DMA Real Ball Image Crop Test (4KB Boundary Case) ---\r\n");

    u32 *src_ptr = (u32 *)BRAM_READ_ADDR;
    u32 *dst_ptr = (u32 *)BRAM_WRITE_ADDR;

    // [Step 1] 원본 데이터를 소스 BRAM으로 복사
    xil_printf("1. Copying Image Data...\r\n");
    // 메모리 범위를 벗어나지 않도록 안전하게 32KB(8192워드) 내에서 복사
    u32 max_copy = (IMG_WIDTH * IMG_HEIGHT > 8192) ? 8192 : (IMG_WIDTH * IMG_HEIGHT); 
    for(int i = 0; i < max_copy; i++) {
        src_ptr[i] = image_data_ball_60[i]; // 헤더 파일의 데이터를 BRAM으로 전송
    }

    u32 full_w = IMG_WIDTH;   // 원본 가로 (예: 80 or 60)
    u32 full_h = IMG_HEIGHT;  // 원본 세로 (예: 80 or 60)
    
    // [Step 2] 크롭 규격 설정 (21x21 크기)
    u32 crop_w_pixels = 21; 
    u32 crop_h = 21;        

    // [Step 3] DMA 시작 주소 설정 (핵심 디버깅 포인트)
    // 0x0FD0은 4KB 경계인 0x1000(4096) 바로 전 주소입니다.
    // 첫 줄(84바이트) 전송 중에 반드시 4KB 경계를 뚫고 지나가게 설계된 "고난도 테스트" 주소입니다.
    u32 start_addr = BRAM_READ_ADDR + 0x0FD0; 
    
    // [Step 4] DMA IP 레지스터 세팅
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_SRC_ADDR,   start_addr);        
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_DST_ADDR,   BRAM_WRITE_ADDR);   
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_WIDTH,  crop_w_pixels * 4); // 84 Bytes (21*4)
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_HEIGHT, crop_h);            // 21 Rows
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_STRIDE, full_w * 4);        // 320 Bytes (80*4)
    
    // [Step 5] 목적지 초기화 (이전 결과 잔상 제거)
    xil_printf("Zeroing Destination BRAM...\r\n");
    for(u32 i = 0; i < (80 * 80); i++) {
        dst_ptr[i] = 0;
    }
    
    // [Step 6] DMA 실행 및 완료 대기
    xil_printf("2. Triggering DMA...\r\n");
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x01); 
    
    int timeout = 0;
    while((Xil_In32(DMA_CTRL_BASE_ADDR + REG_STAT_DONE) & 0x01) == 0) {
        if(timeout++ > 1000000) { xil_printf("TIMEOUT! DMA is stuck (Maybe 4KB issue?).\r\n"); break; }
    }

    // [Step 7] 결과 검증 로직 (더 직관적으로 수정됨)
    int errors = 0;
    // 검증용 소스 포인터를 DMA가 읽기 시작한 'start_addr'로 고정하여 계산을 단순화합니다.
    u32 *verify_src_ptr = (u32 *)start_addr; 

    for (u32 y = 0; y < crop_h; y++) {
        for (u32 x = 0; x < crop_w_pixels; x++) {
            // 소스 인덱스: 원본의 Stride(full_w)를 기준으로 한 줄씩 내려감
            u32 src_idx = y * full_w + x; 
            // 목적지 인덱스: 잘라낸 폭(crop_w_pixels)만큼 촘촘하게 쌓임
            u32 dst_idx = y * crop_w_pixels + x; 
            
            if (verify_src_ptr[src_idx] != dst_ptr[dst_idx]) {
                errors++;
            }
        }
    }

    // [Step 8] 최종 레포트
    if(errors == 0) xil_printf(">>> 2D BALL CROP SUCCESS! (4KB Boundary Passed)\r\n");
    else           xil_printf(">>> 2D BALL CROP FAIL (Errors: %d)\r\n", errors);

    cleanup_platform();
    return 0;
}