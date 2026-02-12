import csv
import random
import os


def generate_test_env():
    # 경로 설정
    current_dir = os.path.dirname(os.path.abspath(__file__))
    source_dir = os.path.join(current_dir, "../source")
    if not os.path.exists(source_dir): os.makedirs(source_dir)

    mem_dict = {}
    scenarios = []

    # 주소 및 크기 설정
    SRC_BASE = 0xC0000000
    DST_BASE = 0xC2000000
    TOTAL_SIZE = 32768  # 32KB
    BURST_SIZE = 64  # 64바이트씩 점핑
    WORD_COUNT = TOTAL_SIZE // 4
    NUM_STEPS = TOTAL_SIZE // BURST_SIZE

    print(f"🏗️  32KB 랜덤 데이터 생성 중...")
    for offset in range(0, TOTAL_SIZE, 4):
        addr = SRC_BASE + offset
        mem_dict[addr] = random.getrandbits(32)

    # 1. stimulus.h 생성 (실제 메모리 데이터)
    header_path = os.path.join(source_dir, "stimulus.h")
    with open(header_path, "w") as f:
        f.write("#ifndef STIMULUS_H\n#define STIMULUS_H\n\n")
        f.write(f"unsigned int stimulus_data[{WORD_COUNT}] = {{\n    ")
        for i, addr in enumerate(sorted(mem_dict.keys())):
            f.write(f"0x{mem_dict[addr]:08x}")
            if i < WORD_COUNT - 1: f.write(", ")
            if (i + 1) % 8 == 0: f.write("\n    ")
        f.write("\n};\n\n#endif")

    # 2. generator.h 생성 (라벨링용 정답지 구조체)
    gen_header_path = os.path.join(source_dir, "generator.h")
    with open(gen_header_path, "w") as f:
        f.write("#ifndef GENERATOR_H\n#define GENERATOR_H\n\n")
        f.write("typedef struct {\n")
        f.write("    int id;\n")
        f.write("    unsigned int src_addr;\n")
        f.write("    unsigned int dst_addr;\n")
        f.write("    int length;\n")
        f.write("    unsigned int golden_data[16]; // 64바이트 정답 데이터\n")
        f.write("} TestCase;\n\n")

        f.write(f"TestCase test_scenarios[{NUM_STEPS}] = {{\n")

        for i in range(NUM_STEPS):
            jump_offset = i * BURST_SIZE
            src_addr = SRC_BASE + jump_offset
            dst_addr = DST_BASE + jump_offset

            f.write(f"    {{ {i}, 0x{src_addr:08x}, 0x{dst_addr:08x}, {BURST_SIZE}, {{")

            # 해당 구간 16개 워드 정답 데이터 채우기
            words = []
            for w_idx in range(16):
                word_addr = src_addr + (w_idx * 4)
                words.append(f"0x{mem_dict[word_addr]:08x}")

            f.write(", ".join(words))
            f.write("} }")
            if i < NUM_STEPS - 1: f.write(",")
            f.write("\n")

        f.write("};\n\n#endif")

    print(f"✅ 생성 완료!")
    print(f" - stimulus.h: 실제 데이터 (32KB)")
    print(f" - generator.h: 라벨링 정답지 ({NUM_STEPS}개 테스트 케이스)")


if __name__ == "__main__":
    generate_test_env()