"""
파일명: TB_Final_System.py
설명: TOP_DMA 클래스를 직접 인스턴스화하여 검증하는 '진짜' 통합 테스트
"""
from sim.verilogRTL.translateModel.TOP_DMA import TopDMA  # ★ 이제 진짜 TopDMA를 불러옵니다!


# --- 메모리 모델 (Slave 역할) ---
class Mock_Slave_Memory:
    def __init__(self, src_data):
        self.mem = src_data.copy()
        self.dest_mem = {}

        # Read Channel State
        self.r_active = False
        self.r_burst_len = 0
        self.r_cnt = 0
        self.r_addr = 0

        # Write Channel State
        self.w_offset_map = {}  # 주소별 오프셋

    # [읽기 응답] RM이 요청하면 데이터를 줌
    def handle_read(self, arvalid, araddr, arlen, rready):
        if not self.r_active and arvalid:
            self.r_active = True
            self.r_addr = araddr
            self.r_burst_len = arlen + 1
            self.r_cnt = 0
            return 1, 0, 0, 0  # Address Phase (1 cycle latency)

        if self.r_active:
            rdata = self.mem.get(self.r_addr, 0x0)
            rlast = 1 if (self.r_cnt == self.r_burst_len - 1) else 0

            if rready:
                self.r_addr += 4
                self.r_cnt += 1
                if self.r_cnt == self.r_burst_len:
                    self.r_active = False
            return 1, 1, rlast, rdata
        return 1, 0, 0, 0

    # [쓰기 처리] WM이 요청하면 데이터를 받아서 저장
    def handle_write(self, awvalid, awaddr, wvalid, wdata):
        if awvalid:
            self.w_offset_map[awaddr] = 0

        if wvalid:
            # 가장 최근에 받은 주소를 기준으로 오프셋 계산 (단순화 모델)
            if self.w_offset_map:
                target_base = sorted(self.w_offset_map.keys())[-1]
                offset = self.w_offset_map[target_base]

                self.dest_mem[target_base + offset] = wdata
                self.w_offset_map[target_base] = offset + 4


def run_final_test():
    print("\n" + "=" * 80)
    print(" [FINAL] TOP_DMA Integration Test (CPU -> Registers -> Logic -> Memory)")
    print("=" * 80)

    # 1. DMA 컨트롤러 생성 (TopDMA 인스턴스)
    dma = TopDMA()

    # 2. 테스트 데이터 준비 (128 Bytes 전송)
    SRC = 0x1000
    DST = 0x5000
    LEN = 128
    src_data = {SRC + i * 4: 0x10 + i for i in range(LEN // 4)}
    memory = Mock_Slave_Memory(src_data)

    print(f"Scenario: CPU writes registers to copy {LEN} bytes.")

    # 3. CPU가 레지스터 설정 (SW 동작 모사)
    dma.reg_src_addr = SRC
    dma.reg_dst_addr = DST
    dma.reg_length = LEN
    dma.reg_start = 1  # ★ Start 버튼 꾹!

    print(f"CPU Config -> Start: {dma.reg_start}, Src: 0x{SRC:X}, Dst: 0x{DST:X}, Len: {LEN}")
    print("-" * 80)
    print(f"{'Cyc':<4} | {'RM':<5} {'ARVal':<5} | {'FIFO':<4} | {'WM':<5} {'WVal':<5} | {'Status'}")
    print("-" * 80)

    # 4. 시뮬레이션 루프
    for cyc in range(100):
        # [A] 현재 TopDMA의 상태를 보고 Slave(메모리)가 어떻게 반응할지 계산
        # (주의: 실제 하드웨어는 동시에 일어나지만, 시뮬에선 순서대로 처리해야 함)

        # 1. RM이 보낼 신호 미리 보기 (이번 턴의 요청)
        curr_arlen = dma.rm.get_current_arlen()

        # 2. 메모리(Slave) 동작
        # Read 응답 생성
        s_arready, s_rvalid, s_rlast, s_rdata = memory.handle_read(
            dma.rm.arvalid, dma.rm.current_addr, curr_arlen, not dma.fifo.full
        )

        # Write 응답 처리 (이전 사이클 결과를 반영)
        # WM 상태를 가져오기 위해 직접 접근은 안 좋지만, 파이썬 모델의 한계로 직접 씀
        # 실제로는 dma.step 결과로 처리하는 게 더 깔끔함. 아래에서 처리.

        # [B] TopDMA 1클럭 실행!
        out = dma.step(
            arready=s_arready, rvalid=s_rvalid, rlast=s_rlast, rdata=s_rdata,
            awready=1, wready=1, bvalid=1  # Write 쪽은 항상 준비됨 가정
        )

        # [C] 메모리에 쓰기 (Write Master 출력 처리)
        memory.handle_write(
            out['wm']['awvalid'], out['wm']['awaddr'],
            out['wm']['wvalid'], out['wm']['wdata']
        )

        # [D] 로그 출력
        rm_st = ["IDLE", "ADDR", "DATA"][dma.rm.state]
        wm_st = ["IDLE", "AW", "W", "B"][dma.wm.state]
        status_str = "DONE" if out['status'] else "RUN"

        # 간략한 로그 (변화가 있을 때만 찍거나 주기적으로 찍음)
        if cyc < 20 or out['status'] == 1 or cyc % 10 == 0:
            print(
                f"{cyc:<4} | {rm_st:<5} {out['rm']['arvalid']:<5} | {out['fifo_cnt']:<4} | {wm_st:<5} {out['wm']['wvalid']:<5} | {status_str}")

        if out['status'] == 1:
            print("-" * 80)
            print(f"✅ Interrupt Received! (DMA Done) at Cycle {cyc}")
            print(f"   Check Start Register: {dma.reg_start} (Should be 0 - Auto Cleared)")
            break

    # 5. 결과 검증
    print("-" * 80)
    if len(memory.dest_mem) == LEN // 4:
        print("✅ SUCCESS: Data copied successfully via TopDMA Wrapper!")
    else:
        print(f"❌ FAIL: Missing data. Count: {len(memory.dest_mem)}")


if __name__ == "__main__":
    run_final_test()