#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"       // Xil_In32, Xil_Out32 등 하드웨어 I/O 함수 포함
#include "xparameters.h"  // Vivado에서 설정한 하드웨어 주소 정보 포함
#include "image_data_ball_80.h" // 80x80 공 이미지 데이터 헤더

// [1] 하드웨어 주소 설정 (Vivado 주소 맵과 일치해야 함)
#define DMA_CTRL_BASE_ADDR   XPAR_TOP_DMA_2D_0_BASEADDR // 2D DMA 컨트롤러 기지 주소
#define BRAM_READ_ADDR       0xC0000000                 // 소스 데이터가 저장될 BRAM 시작 주소
#define BRAM_WRITE_ADDR      0xC2000000                 // DMA 결과가 저장될 목적지 BRAM 주소

// [2] DMA 내부 레지스터 오프셋 (Verilog 설계 시 정의한 주소)
#define REG_CTRL_START       0x00  // [Write] 1을 쓰면 DMA 전송 시작
#define REG_STAT_DONE        0x04  // [Read] 전송 완료 시 1이 됨
#define REG_SRC_ADDR         0x08  // [Write] 읽어올 시작 주소 (첫 번째 픽셀 위치)
#define REG_DST_ADDR         0x0C  // [Write] 저장할 시작 주소
#define REG_IMG_WIDTH        0x10  // [Write] 한 줄에서 실제로 옮길 바이트 수 (폭)
#define REG_IMG_HEIGHT       0x14  // [Write] 총 몇 줄을 옮길 것인가 (높이)
#define REG_IMG_STRIDE       0x18  // [Write] 원본 이미지의 실제 가로 폭 (다음 줄로 가기 위한 점프 거리)

int main() {
    init_platform();
    xil_printf("\r\n--- 2D DMA Real Ball Image Crop Test ---\r\n");

    // 메모리 접근을 위한 32비트 포인터 선언
    u32 *src_ptr = (u32 *)BRAM_READ_ADDR;
    u32 *dst_ptr = (u32 *)BRAM_WRITE_ADDR;

    // [Step 1] 테스트용 소스 데이터 준비
    // C 코드 내의 배열(Flash/DDR)에 있는 데이터를 실제 하드웨어가 읽을 소스 BRAM으로 복사합니다.
    xil_printf("1. Copying Image Data...\r\n");
    // Basys3의 BRAM 용량(32KB)을 넘지 않도록 최대 8,192워드(32KB)까지만 안전하게 복사
    u32 max_copy = (IMG_WIDTH * IMG_HEIGHT > 8192) ? 8192 : (IMG_WIDTH * IMG_HEIGHT); 
    for(int i = 0; i < max_copy; i++) {
        src_ptr[i] = image_data_ball[i];
    }

    // 원본 이미지 규격 (80x80)
    u32 full_w = IMG_WIDTH;   
    u32 full_h = IMG_HEIGHT;  
    
    // [Step 2] 크롭(Crop) 영역 설정
    // 80x80 이미지의 정중앙에 있는 21x21 영역을 선택 (반지름 10.5인 공 타격)
    u32 x_start = 30; 
    u32 y_start = 30;
    u32 crop_w_pixels = 21; // 가로 21픽셀
    u32 crop_h = 21;        // 세로 21줄

    // [Step 3] DMA 시작 주소 계산
    // 2D 이미지에서 (x, y) 좌표의 1차원 주소 = 시작주소 + (y * 가로폭 + x) * 4바이트
    u32 start_addr = BRAM_READ_ADDR + (y_start * full_w + x_start) * 4;

    // [Step 4] DMA 하드웨어 레지스터 설정
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_SRC_ADDR,   start_addr);        // 읽기 시작점 설정
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_DST_ADDR,   BRAM_WRITE_ADDR);   // 쓰기 시작점 설정
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_WIDTH,  crop_w_pixels * 4); // 한 줄당 84바이트(21픽셀*4)
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_HEIGHT, crop_h);            // 총 21줄
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_STRIDE, full_w * 4);        // 원본 줄간격 320바이트(80픽셀*4)
    
    // [Step 5] 결과 확인을 위한 클린 테스트 준비
    // 목적지 BRAM을 0으로 밀어서, 이전 테스트 결과와 섞이지 않게 합니다.
    xil_printf("Zeroing Destination BRAM...\r\n");
    for(u32 i = 0; i < (80 * 80); i++) {
        dst_ptr[i] = 0;
    }
    
    // [Step 6] DMA 트리거 및 완료 대기
    xil_printf("2. Triggering DMA...\r\n");
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x01); // 전송 시작!
    
    int timeout = 0;
    // Done 신호가 올 때까지 무한 루프 (하드웨어가 멈췄을 경우를 대비해 타임아웃 처리)
    while((Xil_In32(DMA_CTRL_BASE_ADDR + REG_STAT_DONE) & 0x01) == 0) {
        if(timeout++ > 1000000) { xil_printf("TIMEOUT!\r\n"); break; }
    }

    // [Step 7] 소프트웨어 검증 (하드웨어가 잘 옮겼는지 확인)
    int errors = 0;
    for (u32 y = 0; y < crop_h; y++) {
        for (u32 x = 0; x < crop_w_pixels; x++) {
            // 원본 데이터의 인덱스 (80픽셀 폭 기준 점프)
            u32 src_idx = (y_start + y) * full_w + (x_start + x);
            
            // 목적지 데이터의 인덱스 (20픽셀 폭 기준 촘촘하게 저장됨)
            // 하드웨어가 Write Stride를 폭(20)에 맞췄으므로 촘촘하게 배치된 데이터를 확인합니다.
            u32 dst_idx = y * crop_w_pixels + x; 
            
            // 원본과 복사본 비교
            if (src_ptr[src_idx] != dst_ptr[dst_idx]) errors++;
        }
    }
    
    // 최종 결과 출력
    if(errors == 0) xil_printf(">>> 2D BALL CROP SUCCESS!\r\n");
    else           xil_printf(">>> 2D BALL CROP FAIL (Errors: %d)\r\n", errors);

    cleanup_platform();
    return 0;
}