import csv
import random
import os


def generate_test_env():
    # 경로 설정 (기존 구조 유지)
    current_dir = os.path.dirname(os.path.abspath(__file__))
    source_dir = os.path.join(current_dir, "../source")
    if not os.path.exists(source_dir): os.makedirs(source_dir)

    scenarios = []
    mem_dict = {}

    # 주소 및 크기 설정
    SRC_BASE = 0xC0000000
    DST_BASE = 0xC2000000
    TOTAL_SIZE = 32768  # 전체 양: 32KB
    BURST_SIZE = 64  # 한 번에 보낼 양: 64바이트
    NUM_STEPS = TOTAL_SIZE // BURST_SIZE  # 총 512번의 점핑

    print(f"🏗️  BRAM 32KB 전체 영역(소스)에 데이터를 꽉 채우는 중...")
    # 1. 0xC0000000 ~ 0xC0007FFC 까지 빈틈없이 랜덤 데이터 생성
    for offset in range(0, TOTAL_SIZE, 4):
        addr = SRC_BASE + offset
        mem_dict[addr] = f"{random.getrandbits(32):08x}"

    print(f"📑 64바이트씩 점핑하며 총 {NUM_STEPS}개의 정답지(라벨) 생성 중...")
    # 2. 64바이트 단위로 주소를 점핑하며 시나리오 생성
    for i in range(NUM_STEPS):
        jump_offset = i * BURST_SIZE
        src_addr = SRC_BASE + jump_offset
        dst_addr = DST_BASE + jump_offset

        # 해당 64바이트 구간의 실제 데이터(16개 워드)를 추출해서 라벨링
        row_data = {
            "id": i,
            "src_addr": hex(src_addr),
            "dst_addr": hex(dst_addr),
            "length": BURST_SIZE,
            "status": "READY"
        }

        # word_0 ~ word_15 컬럼에 실제 정답 데이터를 박아넣음 (라벨링)
        for w_idx in range(16):
            word_addr = src_addr + (w_idx * 4)
            row_data[f"word_{w_idx}"] = f"0x{mem_dict[word_addr]}"

        scenarios.append(row_data)

    # 3. stimulus.mem 저장 (주소:데이터 형식)
    with open(os.path.join(source_dir, "stimulus.mem"), "w") as f:
        for addr, data in sorted(mem_dict.items()):
            f.write(f"{hex(addr)}:{data}\n")

    # 4. scenarios.csv 저장 (512줄의 완벽한 정답지)
    with open(os.path.join(source_dir, "scenarios.csv"), "w", newline="") as f:
        if scenarios:
            writer = csv.DictWriter(f, fieldnames=scenarios[0].keys())
            writer.writeheader()
            writer.writerows(scenarios)

    print(f"✅ 생성 완료!")
    print(f" - scenarios.csv: 64B씩 점핑하는 512개의 정답 데이터 라벨링 완료")
    print(f" - stimulus.mem: 0xC0000000 ~ 0xC0007FFF 전체 데이터 꽉 채움")


if __name__ == "__main__":
    generate_test_env()