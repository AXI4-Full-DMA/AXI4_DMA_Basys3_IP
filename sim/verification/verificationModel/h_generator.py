import csv
import random
import os


def generate_test_env():
    # 경로 설정
    current_dir = os.path.dirname(os.path.abspath(__file__))
    source_dir = os.path.join(current_dir, "../source")
    if not os.path.exists(source_dir): os.makedirs(source_dir)

    mem_dict = {}

    # 주소 및 크기 설정
    SRC_BASE = 0xC0000000
    TOTAL_SIZE = 32768  # 32KB
    WORD_COUNT = TOTAL_SIZE // 4  # 8192개 워드

    # 1. 랜덤 데이터 생성 (32bit 숫자 형식으로 저장)
    for offset in range(0, TOTAL_SIZE, 4):
        addr = SRC_BASE + offset
        mem_dict[addr] = random.getrandbits(32)

    # 2. .h 헤더 파일로 저장
    header_path = os.path.join(source_dir, "stimulus.h")
    with open(header_path, "w") as f:
        f.write("#ifndef STIMULUS_H\n")
        f.write("#define STIMULUS_H\n\n")
        f.write(f"// Total Size: {TOTAL_SIZE} Bytes (32KB)\n")
        f.write(f"unsigned int stimulus_data[{WORD_COUNT}] = {{\n")

        # 데이터를 8192개 나열
        for i, addr in enumerate(sorted(mem_dict.keys())):
            val = mem_dict[addr]
            f.write(f"0x{val:08x}")
            if i < WORD_COUNT - 1:
                f.write(", ")
            if (i + 1) % 8 == 0:  # 8개마다 줄바꿈 (가독성)
                f.write("\n    ")

        f.write("\n};\n\n")
        f.write("#endif // STIMULUS_H\n")

    print(f"✅ 생성 완료!")
    print(f" - stimulus.h: C/C++에서 바로 include 가능한 헤더 파일 생성 완료")
    print(f" - 데이터 개수: {WORD_COUNT}개 (32-bit words)")


if __name__ == "__main__":
    generate_test_env()