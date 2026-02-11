"""
파일명: TB_Large_Transfer.py
목적: 64KB 대용량 데이터 전송 시뮬레이션 (Golden Model 검증)
"""
from sim.verilogRTL.translateModel.readMasterVerilog import ReadMaster
from sim.verilogRTL.translateModel.writeMasterVerilog import WriteMaster
from sim.verilogRTL.translateModel.FIFO import FIFO


class Mock_Memory:
    def __init__(self, src_data):
        self.mem = src_data.copy()
        self.dest_mem = {}
        # Read State
        self.r_active, self.r_burst_len, self.r_cnt, self.r_addr = False, 0, 0, 0
        # Write State
        self.w_offset_map = {}

    def handle_read(self, arvalid, araddr, arlen, rready):
        if not self.r_active and arvalid:
            self.r_active = True
            self.r_addr = araddr
            self.r_burst_len = arlen + 1
            self.r_cnt = 0
            return 1, 0, 0, 0  # Address Phase

        if self.r_active:
            rdata = self.mem.get(self.r_addr, 0x0)
            rlast = 1 if (self.r_cnt == self.r_burst_len - 1) else 0
            if rready:
                self.r_addr += 4
                self.r_cnt += 1
                if self.r_cnt == self.r_burst_len: self.r_active = False
            return 1, 1, rlast, rdata
        return 1, 0, 0, 0

    def handle_write(self, awvalid, awaddr, wvalid, wdata):
        if awvalid: self.w_offset_map[awaddr] = 0
        if wvalid:
            target_base = sorted(self.w_offset_map.keys())[-1] if self.w_offset_map else 0
            offset = self.w_offset_map.get(target_base, 0)
            self.dest_mem[target_base + offset] = wdata
            self.w_offset_map[target_base] = offset + 4


def run_64kb_test():
    print("\n" + "=" * 80)
    print(" [GOLDEN MODEL] 64KB Large Transfer Verification")
    print("=" * 80)

    rm = ReadMaster()
    wm = WriteMaster()
    fifo = FIFO(depth=1024)  # 4KB FIFO

    # 1. 64KB 설정 (65536 Bytes = 16384 Words)
    SRC_ADDR = 0x10000000
    DST_ADDR = 0x20000000
    LEN = 64 * 1024  # 65536 Bytes
    TOTAL_WORDS = LEN // 4

    print(f"Scenario: Copy {LEN} Bytes ({TOTAL_WORDS} Words)")
    print(f"Source: 0x{SRC_ADDR:X} -> Dest: 0x{DST_ADDR:X}")
    print("Generating Data... (Wait a moment)")

    # 데이터 생성 (0, 1, 2, ... 16383)
    src_data = {SRC_ADDR + i * 4: i for i in range(TOTAL_WORDS)}
    memory = Mock_Memory(src_data)

    print("Simulation Start...")
    print("-" * 80)

    start_pulse = 1
    total_cycles = 0

    # 무한 루프 방지를 위한 최대 사이클 (충분히 크게 잡음)
    MAX_CYCLES = TOTAL_WORDS * 4

    while total_cycles < MAX_CYCLES:
        total_cycles += 1

        # --- Hardware Step ---
        curr_arlen = rm.get_current_arlen()
        arready, rvalid, rlast, rdata = memory.handle_read(
            rm.arvalid, rm.current_addr, curr_arlen, not fifo.full
        )

        rm_out = rm.step(start_pulse, SRC_ADDR, LEN, fifo.full, arready, rvalid, rlast, rdata)
        if rm_out['push']: fifo.push(rm_out['data'])

        wm_out = wm.step(start_pulse, DST_ADDR, LEN, fifo.empty, fifo.peek(), 1, 1, 1)
        if wm_out['pop']: fifo.pop()

        memory.handle_write(wm_out['awvalid'], wm_out['awaddr'], wm_out['wvalid'], wm_out['wdata'])

        start_pulse = 0

        # --- Progress Bar (너무 많이 출력하면 느리니까 10%마다 출력) ---
        written_words = len(memory.dest_mem)
        if written_words > 0 and written_words % (TOTAL_WORDS // 10) == 0:
            if wm_out['wvalid']:  # 중복 출력 방지
                percent = (written_words / TOTAL_WORDS) * 100
                print(f"Progress: {percent:.0f}% ({written_words}/{TOTAL_WORDS} Words Copied) - Cycle {total_cycles}")

        # --- 종료 조건 ---
        if rm_out['done'] and wm_out['done']:
            print("-" * 80)
            print(f"✅ All Transfers Done at Cycle {total_cycles}")
            break

    # 2. 결과 검증
    print("-" * 80)
    print("Verifying Data Integrity...")

    if len(memory.dest_mem) != TOTAL_WORDS:
        print(f"❌ FAIL: Count Mismatch! Exp {TOTAL_WORDS}, Act {len(memory.dest_mem)}")
    else:
        mismatch = False
        for i in range(TOTAL_WORDS):
            addr = DST_ADDR + i * 4
            if memory.dest_mem[addr] != i:  # src_data value is 'i'
                print(f"❌ FAIL at index {i}")
                mismatch = True
                break

        if not mismatch:
            print(f"✅ SUCCESS: 64KB ({TOTAL_WORDS} words) copied perfectly!")
            print("   This confirms your Python logic is a robust GOLDEN MODEL.")


if __name__ == "__main__":
    run_64kb_test()