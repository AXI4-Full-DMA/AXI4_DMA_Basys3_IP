"""
파일명: TB_Full_System.py
목적: Read Master + FIFO + Write Master 통합 검증
수정: 로그에 데이터 값(Hex)을 함께 출력하도록 변경
"""
from sim.verilogRTL.translateModel.readMasterVerilog import ReadMaster
from sim.verilogRTL.translateModel.writeMasterVerilog import WriteMaster
from sim.verilogRTL.translateModel.FIFO import FIFO

class Mock_Memory:
    """
    소스 메모리(Read 대상)와 목적지 메모리(Write 대상) 역할을 동시에 수행
    """
    def __init__(self, src_data):
        self.mem = src_data.copy()
        self.dest_mem = {}

        # Read Channel 상태
        self.r_active = False
        self.r_burst_len = 0
        self.r_cnt = 0
        self.r_addr = 0

        # Write Channel 상태
        self.w_offset_map = {}

    def handle_read(self, arvalid, araddr, arlen, rready):
        if not self.r_active and arvalid:
            self.r_active = True
            self.r_addr = araddr
            self.r_burst_len = arlen + 1
            self.r_cnt = 0
            return 1, 0, 0, 0

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

    def handle_write(self, awvalid, awaddr, wvalid, wdata, wlast):
        if awvalid:
            self.w_offset_map[awaddr] = 0

        if wvalid:
            target_base = sorted(self.w_offset_map.keys())[-1] if self.w_offset_map else 0
            offset = self.w_offset_map.get(target_base, 0)

            self.dest_mem[target_base + offset] = wdata
            self.w_offset_map[target_base] = offset + 4

def run_full_system_test():
    print("\n" + "="*90)
    print(" [FINAL TEST] Full DMA System Verification (Data Values Visible)")
    print("="*90)

    # 1. 모듈 연결
    rm = ReadMaster()
    wm = WriteMaster()
    fifo = FIFO(depth=1024)

    # 2. 시나리오: 128 Bytes 전송
    SRC_ADDR = 0x1000
    DST_ADDR = 0x5000
    LEN = 128

    # 데이터 생성 (0x10, 0x11, 0x12 ...)
    src_data = {SRC_ADDR + i*4: 0x10+i for i in range(LEN//4)}
    memory = Mock_Memory(src_data)

    print(f"Scenario: Copy {LEN} Bytes from 0x{SRC_ADDR:X} to 0x{DST_ADDR:X}")
    print("-" * 90)
    print(f"{'Cyc':<4} | {'RM':<5} | {'FIFO':<4} | {'WM':<5} | {'Action (Data)'}")
    print("-" * 90)

    start_pulse = 1

    for cyc in range(100):
        # [A] Master Request Check
        curr_arlen = rm.get_current_arlen()

        # 1. Memory Read Response
        arready, rvalid, rlast, rdata = memory.handle_read(
            rm.arvalid, rm.current_addr, curr_arlen, not fifo.full
        )

        # 2. Read Master Step
        rm_out = rm.step(
            start_pulse, SRC_ADDR, LEN, fifo.full,
            arready, rvalid, rlast, rdata
        )
        if rm_out['push']: fifo.push(rm_out['data'])

        # 3. Write Master Step
        wm_out = wm.step(
            start_pulse, DST_ADDR, LEN, fifo.empty, fifo.peek(),
            1, 1, 1
        )
        if wm_out['pop']: fifo.pop()

        # 4. Memory Write
        memory.handle_write(
            wm_out['awvalid'], wm_out['awaddr'],
            wm_out['wvalid'], wm_out['wdata'], wm_out['wlast']
        )

        start_pulse = 0

        # --- [B] 로그 출력 (수정된 부분) ---
        rm_st = ["IDLE", "ADDR", "DATA"][rm.state]
        wm_st = ["IDLE", "AW", "W", "B"][wm.state]
        action = ""

        # ★ 여기! 데이터 값(Hex)을 같이 찍어줍니다.
        if rm_out['arvalid']: action += f"[R_Req:{curr_arlen+1}] "
        if rm_out['push']:    action += f"RM->FIFO(0x{rm_out['data']:02X}) "  # 읽은 데이터

        if wm_out['awvalid']: action += f"[W_Req] "
        if wm_out['wvalid']:  action += f"FIFO->WM(0x{wm_out['wdata']:02X}) " # 쓰는 데이터

        # 변화가 있거나 매 사이클 출력
        print(f"{cyc:<4} | {rm_st:<5} | {fifo.count:<4} | {wm_st:<5} | {action}")

        # --- [C] 종료 조건 ---
        if rm_out['done'] and wm_out['done']:
            print("-" * 90)
            print(f"✅ All Transfers Done at Cycle {cyc}")
            break

    # 4. 결과 검증
    print("-" * 90)
    print(f"Source Data Count: {len(src_data)}")
    print(f"Dest Data Count:   {len(memory.dest_mem)}")

    is_fail = False
    for i in range(LEN//4):
        s_addr = SRC_ADDR + i*4
        d_addr = DST_ADDR + i*4
        s_val = src_data[s_addr]
        d_val = memory.dest_mem.get(d_addr, -1)

        if s_val != d_val:
            print(f"❌ Mismatch! Addr 0x{d_addr:X}: Exp 0x{s_val:X} != Act 0x{d_val:X}")
            is_fail = True

    if not is_fail:
        print("✅ SUCCESS: 128 Bytes copied perfectly!")
    else:
        print("❌ FAIL: Data integrity error.")

if __name__ == "__main__":
    run_full_system_test()