# 02_Python_Verification/models/dma_golden.py

class DMAGoldenModel:
    def __init__(self, initial_mem):
        # 원본 데이터 보호를 위해 .copy()를 사용함.
        # 이게 없으면 테스트 하나 끝날 때마다 원본 메모리가 오염됨.
        self.memory = initial_mem.copy()

    def run_1d_transfer(self, src_addr, dst_addr, length):
        """1D DMA 전송의 논리적 정답 계산"""
        for i in range(0, length, 4):
            current_src = src_addr + i
            current_dst = dst_addr + i

            # 소스에서 데이터 읽어서 목적지에 쓰기
            data = self.memory.get(current_src, 0)
            self.memory[current_dst] = data

        return self.memory  # 전송 완료된 메모리 상태 반환