def check_axi_4kb_boundary(addr, burst_len, data_width_bytes=4):
    """
    AXI Rule: A burst must not cross a 4KB boundary.
    4KB Boundary = 0x1000 (4096 bytes)
    """
    # 전송 시작 주소와 마지막 주소 계산
    start_addr = addr
    end_addr = addr + (burst_len * data_width_bytes) - 1

    # 4KB 경계 침범 여부 확인 (주소의 상위 비트가 달라지는지 체크)
    if (start_addr & ~0xFFF) != (end_addr & ~0xFFF):
        error_msg = f"[ERROR] AXI 4KB Boundary Violated!\n" \
                    f"  Start Addr: 0x{start_addr:08X}\n" \
                    f"  End Addr:   0x{end_addr:08X}\n" \
                    f"  Next 4KB:   0x{(start_addr & ~0xFFF) + 0x1000:08X}"
        raise ValueError(error_msg)
    return True

# 활용 예시 (Master Step 함수 내부에 삽입)
# if arvalid:
#    check_axi_4kb_boundary(araddr, arlen + 1)