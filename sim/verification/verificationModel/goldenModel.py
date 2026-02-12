class DMAGoldenModel:
    def __init__(self, initial_mem):
        # 초기 메모리 상태 저장 (Dictionary 형태: {주소: 데이터})
        self.memory = initial_mem.copy()
        self.expected_transactions = []  # 하드웨어가 발생시켜야 할 예상 트랜잭션 기록

    def run_1d_transfer(self, src_addr, dst_addr, length):
        """
        1D DMA 전송의 논리적 정답 및 트랜잭션 시나리오 계산
        """
        self.expected_transactions = []
        rem_len = length
        curr_src = src_addr
        curr_dst = dst_addr

        # [핵심 알고리즘] AXI4 표준에 따른 트랜잭션 분할 로직
        while rem_len > 0:
            # 1. 4KB 경계 및 최대 버스트(64B)를 고려한 전송 길이 계산
            next_4kb_boundary = 0x1000 - (curr_src & 0xFFF)
            max_burst = 64  # 하드웨어 스펙: 최대 16 beats (64 bytes)

            # 실제 하드웨어가 한 번에 보낼 길이를 결정하는 알고리즘
            this_step_len = min(rem_len, next_4kb_boundary, max_burst)

            # 트랜잭션 기록 (디버깅용 정답지)
            self.expected_transactions.append({
                'src': curr_src,
                'dst': curr_dst,
                'len': this_step_len
            })

            # 2. 실제 메모리 데이터 이동 (결과 정답지)
            for i in range(0, this_step_len, 4):
                data = self.memory.get(curr_src + i, 0)
                self.memory[curr_dst + i] = data

            # 3. 주소 및 남은 길이 업데이트
            curr_src += this_step_len
            curr_dst += this_step_len
            rem_len -= this_step_len

        return self.memory

    def run_2d_transfer(self, src_addr, dst_addr, width, height, stride):
        """
        2D DMA(영상 크롭 등)를 위한 확장 알고리즘
        """
        for h in range(height):
            line_src = src_addr + (h * stride)
            line_dst = dst_addr + (h * width)
            # 매 줄마다 1D 전송 알고리즘 재사용
            self.run_1d_transfer(line_src, line_dst, width)
        return self.memory

    def verify(self, rtl_output_mem):
        """
        실제 하드웨어 결과(rtl_output_mem)와 정답지를 비교하는 알고리즘
        """
        errors = []
        for addr, expected_val in self.memory.items():
            actual_val = rtl_output_mem.get(addr, None)
            if actual_val != expected_val:
                errors.append(f"Addr 0x{addr:08X}: Exp 0x{expected_val:08X}, Act 0x{actual_val}")

        return len(errors) == 0, errors