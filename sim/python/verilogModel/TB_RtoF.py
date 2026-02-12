"""
파일명: TB_RtoF.py
목적: Read Master -> FIFO 데이터 흐름 검증 (Fix: ARLEN 전달 오류 수정)
"""
from readMasterVerilog import ReadMaster
from FIFO import FIFO

class Mock_Read_Slave:
    def __init__(self, data_map):
        self.mem = data_map
        self.active = False
        self.burst_len = 0
        self.cnt = 0
        self.addr = 0

    def respond(self, arvalid, araddr, arlen, rready):
        arready_out = 1
        rvalid_out = 0
        rlast_out = 0
        rdata_out = 0

        # [1] Address Phase
        if not self.active and arvalid:
            self.active = True
            self.addr = araddr
            self.burst_len = arlen + 1 # Master가 요청한 길이 저장
            self.cnt = 0
            # Latency 1 Cycle을 위해 바로 리턴
            return arready_out, 0, 0, 0

        # [2] Data Phase
        if self.active:
            rvalid_out = 1
            rdata_out = self.mem.get(self.addr, 0x0)

            if self.cnt == self.burst_len - 1:
                rlast_out = 1

            if rready:
                self.addr += 4
                self.cnt += 1
                if self.cnt == self.burst_len:
                    self.active = False

        return arready_out, rvalid_out, rlast_out, rdata_out

def run_read_test():
    print("\n" + "="*60)
    print(" [TEST 1] Read Path Verification (Memory -> RM -> FIFO)")
    print("="*60)

    rm = ReadMaster()
    fifo = FIFO(depth=1024)

    SRC_ADDR = 0x1000
    LEN = 64 # 16 Words
    source_data = {SRC_ADDR + i*4: 0xA0+i for i in range(LEN//4)}
    slave = Mock_Read_Slave(source_data)

    print(f"Scenario: Read {LEN} Bytes from 0x{SRC_ADDR:X}")
    print(f"{'Cyc':<4} | {'State':<5} | {'ARValid':<7} | {'Push':<4} | {'Data':<8} | {'FIFO Cnt'}")
    print("-" * 60)

    rm_start = 1

    for cyc in range(30):
        # ★ 핵심 수정: Master에게 "지금 보내려는 길이가 얼마냐?" 물어봄
        # 이전에는 0(기본값)이 들어갔으나, 이제 계산된 값(15)이 들어감
        current_arlen = rm.get_current_arlen()

        # (1) Slave 동작
        arready, rvalid, rlast, rdata = slave.respond(
            rm.arvalid, rm.current_addr, current_arlen, not fifo.full
        )

        # (2) Master 동작
        out = rm.step(
            rm_start, SRC_ADDR, LEN, fifo.full,
            arready, rvalid, rlast, rdata
        )
        rm_start = 0

        # (3) FIFO Push
        if out['push']:
            fifo.push(out['data'])

        # 로그 출력
        state_str = ["IDLE", "ADDR", "DATA"][rm.state]
        push_str = "YES" if out['push'] else " "
        data_str = f"0x{out['data']:X}" if out['push'] else " - "

        print(f"{cyc:<4} | {state_str:<5} | {out['arvalid']:<7} | {push_str:<4} | {data_str:<8} | {fifo.count}")

        if out['done']:
            print("-" * 60)
            print(f"✅ Read Done at Cycle {cyc}")
            break

    # 최종 검증
    print("-" * 60)
    print(f"Final FIFO Count: {fifo.count} (Expected: {LEN//4})")

    is_correct = True
    for i in range(LEN//4):
        val = fifo.memory[i]
        expected = 0xA0 + i
        if val != expected:
            print(f"❌ Mismatch at index {i}: Exp 0x{expected:X} != Act 0x{val:X}")
            is_correct = False

    if is_correct:
        print("✅ DATA INTEGRITY PASS: Memory content matches FIFO content exactly.")
    else:
        print("❌ DATA INTEGRITY FAIL")

if __name__ == "__main__":
    run_read_test()