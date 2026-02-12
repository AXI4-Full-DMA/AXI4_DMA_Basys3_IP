#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"

// [1] 주소 설정 (xparameters.h에서 이름 확인 필수)
#define DMA_CTRL_BASE_ADDR   XPAR_TOP_DMA_2D_0_BASEADDR 
#define BRAM_READ_ADDR       0xC0000000
#define BRAM_WRITE_ADDR      0xC2000000

// [2] 레지스터 오프셋
#define REG_CTRL_START       0x00
#define REG_STAT_DONE        0x04
#define REG_SRC_ADDR         0x08
#define REG_DST_ADDR         0x0C
#define REG_IMG_WIDTH        0x10
#define REG_IMG_HEIGHT       0x14
#define REG_IMG_STRIDE       0x18

// -------------------------------------------------------------------------
// [3] 함수 정의: Generate_Test_Pattern (몸통이 꼭 있어야 ld 에러가 안 납니다!)
// -------------------------------------------------------------------------
void Generate_Test_Pattern(u32 base_addr, u32 width, u32 height) {
    u32 *mem_ptr = (u32 *)(uintptr_t)base_addr; 
    for (u32 y = 0; y < height; y++) {
        for (u32 x = 0; x < width; x++) {
            u8 red   = (u8)(x * 255 / width);
            u8 green = (u8)(y * 255 / height);
            u32 pixel = (red << 24) | (green << 16) | (0x00 << 8) | 0xFF;
            mem_ptr[y * width + x] = pixel;
        }
    }
}

int main() {
    init_platform();
    xil_printf("\r\n--- 2D DMA Real Crop Test ---\r\n");

    u32 *src_ptr = (u32 *)BRAM_READ_ADDR;
    u32 *dst_ptr = (u32 *)BRAM_WRITE_ADDR;

    // 1. 가상 이미지 생성 (16x16)
    u32 full_w = 16, full_h = 16;
    Generate_Test_Pattern(BRAM_READ_ADDR, full_w, full_h);

    // 2. 크롭 영역 설정 (중앙 4x4)
    u32 x_start = 6, y_start = 6;
    u32 crop_w_pixels = 4, crop_h = 4;
    u32 start_addr = BRAM_READ_ADDR + (y_start * full_w + x_start) * 4;

    // 3. DMA 레지스터 설정
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_SRC_ADDR,   start_addr);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_DST_ADDR,   BRAM_WRITE_ADDR);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_WIDTH,  crop_w_pixels * 4);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_HEIGHT, crop_h);
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_IMG_STRIDE, full_w * 4);

    // 4. 실행 및 대기
    Xil_Out32(DMA_CTRL_BASE_ADDR + REG_CTRL_START, 0x01);
    
    int timeout = 0;
    while((Xil_In32(DMA_CTRL_BASE_ADDR + REG_STAT_DONE) & 0x01) == 0) {
        if(timeout++ > 1000000) { xil_printf("TIMEOUT!\r\n"); break; }
    }

    // 5. 2D 검증 로직
    int errors = 0;
    for (u32 y = 0; y < crop_h; y++) {
        for (u32 x = 0; x < crop_w_pixels; x++) {
            u32 src_idx = (y_start + y) * full_w + (x_start + x);
            u32 dst_idx = y * crop_w_pixels + x;
            if (src_ptr[src_idx] != dst_ptr[dst_idx]) errors++;
        }
    }

    xil_printf("Result: %s (Errors: %d)\r\n", (errors==0)?"PASS":"FAIL", errors);

    cleanup_platform();
    return 0;
}