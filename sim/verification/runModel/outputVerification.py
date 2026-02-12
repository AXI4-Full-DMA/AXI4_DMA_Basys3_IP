import struct
import re
import os
from datetime import datetime

# [설정] 경로 및 베이스 주소
STIM_PATH = "../source/stimulus.h"
BIN_PATH = "../source/result.bin"
BASE_ADDR = 0xC2000000


def verify():
    # 1. stimulus.h 파싱
    with open(STIM_PATH, 'r') as f:
        content = f.read()
    stim_hex = re.findall(r'0x[0-9a-fA-F]+', content)
    stim_data = [int(x, 16) for x in stim_hex]

    # 2. result.bin 읽기 (Big-Endian)
    with open(BIN_PATH, 'rb') as f:
        bin_content = f.read()
        num_elements = len(bin_content) // 4
        actual_data = list(struct.unpack(f'>{num_elements}I', bin_content))

    # 3. 비교 및 출력 (요청하신 형식 그대로)
    total = len(stim_data)
    match_count = 0

    for i in range(total):
        curr_addr = BASE_ADDR + (i * 4)
        exp_val = stim_data[i]
        act_val = actual_data[i] if i < len(actual_data) else 0x0

        if exp_val == act_val:
            match_count += 1
            print(f"✅ match at index 0x{curr_addr:08X} : Exp : {exp_val:08X}, Act : {act_val:08X}")
        else:
            print(f"❌ mismatch at index 0x{curr_addr:08X} : Exp : {exp_val:08X}, Act : {act_val:08X}")

    # 4. 요약 리포트 출력 (시간 포함)
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    status = "PASS" if match_count == total else "FAIL"

    print("\n" + "=" * 55)
    print(" [ DMA VERIFICATION REPORT ]")
    print("=" * 55)
    print(f" * Test Time     : {now}")
    print(f" * Target File   : {os.path.basename(BIN_PATH)} ({len(bin_content)} bytes)")
    print(f" * Total Words   : {total} units")
    print("-" * 55)
    print(f" >> STATUS: [  {status}  ]")
    print(f" >> DETAIL: {match_count}/{total} words matched {int(match_count / total * 100)}%.")
    print("=" * 55 + "\n")


if __name__ == "__main__":
    verify()