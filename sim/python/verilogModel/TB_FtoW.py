"""
파일명: TB_FtoW.py
목적: FIFO -> Write Master -> Memory 쓰기 검증 (Address Logic 수정)
"""
from writeMasterVerilog import WriteMaster
from FIFO import FIFO

def run_write_test():
    print("\n" + "="*60)
    print(" [TEST 2] Write Path Verification (FIFO -> WM -> Memory)")
    print("="*60)

    # 1. 모듈 준비
    wm = WriteMaster()
    fifo = FIFO(depth=1024)

    # 2. FIFO Pre-fill (데이터 채우기)
    LEN = 64 # 16 Words
    print(f"Scenario: Pre-filling FIFO with {LEN} Bytes...")
    expected_mem = {}
    for i in range(LEN//4):
        data = 0xB0 + i
        fifo.push(data)
        expected_mem[0x5000 + i*4] = data # 정답지 생성

    print(f"FIFO Initial Count: {fifo.count}")

    # 3. 목적지 메모리 (Slave Simulation)
    dest_memory = {}
    DST_ADDR = 0x5000

    # ★ 핵심 수정: Slave가 스스로 주소를 관리 (Master 내부 변수 의존 X)
    slave_addr_offset = 0

    # 4. 시뮬레이션
    wm_start = 1

    print(f"{'Cyc':<4} | {'State':<6} | {'AWValid':<7} | {'WValid':<6} | {'WLast':<5} | {'Action'}")
    print("-" * 60)

    for cyc in range(30):
        # (1) Write Master 실행
        # Slave는 항상 준비됨 (Ready=1)
        out = wm.step(
            wm_start, DST_ADDR, LEN, fifo.empty, fifo.peek(),
            1, 1, 1
        )
        wm_start = 0

        # (2) Write 채널 모니터링 (Slave 역할)
        action = ""

        # 주소 채널 확인
        if out['awvalid']:
            action += f"Addr(0x{out['awaddr']:X}) "

        # 데이터 채널 확인 (실제 쓰기 발생)
        if out['wvalid']: # Master Valid & Slave Ready(1)
            # Master 내부 beat_cnt를 쓰지 않고, Slave가 직접 offset 계산
            current_write_addr = wm.current_addr + slave_addr_offset
            dest_memory[current_write_addr] = out['wdata']

            action += f"Write(0x{out['wdata']:X}) -> Mem[0x{current_write_addr:X}]"

            # 다음 주소를 위해 오프셋 증가
            slave_addr_offset += 4

        # FIFO Pop 확인
        if out['pop']:
            fifo.pop()

        state_str = ["IDLE", "AW", "W", "B"][wm.state]
        print(f"{cyc:<4} | {state_str:<6} | {out['awvalid']:<7} | {out['wvalid']:<6} | {out['wlast']:<5} | {action}")

        # 완료 체크
        if out['done']:
            print("-" * 60)
            print(f"✅ Write Done at Cycle {cyc}")
            break

    # 5. 최종 검증
    print("-" * 60)
    print(f"FIFO Final Count: {fifo.count} (Should be 0)")

    # 데이터 전수 조사
    is_correct = True
    if len(dest_memory) != LEN//4:
        print(f"❌ Missing Data: Wrote {len(dest_memory)} words, expected {LEN//4}")
        is_correct = False
    else:
        for addr, val in dest_memory.items():
            exp_val = expected_mem.get(addr, -1)
            if val != exp_val:
                print(f"❌ Data Mismatch at 0x{addr:X}: Act 0x{val:X} != Exp 0x{exp_val:X}")
                is_correct = False
            # else:
            #     print(f"  [OK] Addr 0x{addr:X} = 0x{val:X}")

    if is_correct:
        print("✅ DATA INTEGRITY PASS: All data written correctly!")
    else:
        print("❌ DATA INTEGRITY FAIL")

if __name__ == "__main__":
    run_write_test()