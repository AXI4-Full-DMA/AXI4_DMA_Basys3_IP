import sys
import os
import csv

# [1] 경로 설정 (기존 유지)
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "../../../"))
sys.path.append(os.path.join(project_root, "sim/verilogRTL/translateModel"))
sys.path.append(os.path.join(project_root, "sim/verification/verificationModel"))

from TOP_DMA import TopDMA  #


# [2] 어떤 형식이든 다 읽을 수 있게 고친 메모리 로더
def load_stimulus_mem(filename):
    mem_dict = {}
    SRC_BASE = 0xC0000000  # 주소가 없는 플랫 파일일 경우 0xC0000000부터 채움
    if not os.path.exists(filename):
        print(f"❌ {filename} 파일을 찾을 수 없습니다!")
        return {}
    with open(filename, 'r') as f:
        # 빈 줄 제외하고 한 줄씩 읽기
        lines = [line.strip() for line in f if line.strip()]
        for i, line in enumerate(lines):
            if ':' in line:
                # '0xc0000000:aabbccdd' 형식 처리
                addr_str, val_str = line.split(':')
                mem_dict[int(addr_str, 16)] = int(val_str, 16)
            else:
                # 'aabbccdd' 형식 처리 (0xC0000000부터 4바이트씩 순서대로 박음)
                mem_dict[SRC_BASE + (i * 4)] = int(line, 16)
    return mem_dict


# --- [Slave 모델 및 시뮬레이션 로직 - 기존과 완벽 동일] ---
class Improved_AXI_Slave:
    def __init__(self, initial_mem):
        self.mem = initial_mem.copy()  #
        self.r_active, self.r_addr, self.r_burst_len, self.r_cnt = False, 0, 0, 0
        self.w_addr = 0

    def handle_axi_read(self, arvalid, araddr, arlen, rready):
        arready, rvalid, rlast, rdata = 1, 0, 0, 0
        if not self.r_active and arvalid:
            self.r_active, self.r_addr, self.r_burst_len, self.r_cnt = True, araddr, arlen + 1, 0
            return arready, 0, 0, 0
        if self.r_active:
            rvalid, rdata = 1, self.mem.get(self.r_addr, 0x0)
            rlast = 1 if (self.r_cnt == self.r_burst_len - 1) else 0
            if rready:
                self.r_addr += 4;
                self.r_cnt += 1
                if self.r_cnt == self.r_burst_len: self.r_active = False
        return arready, rvalid, rlast, rdata

    def handle_axi_write(self, awvalid, awaddr, wvalid, wdata):
        if awvalid: self.w_addr = awaddr
        if wvalid:
            self.mem[self.w_addr] = wdata
            self.w_addr += 4


def run_total_verification():
    csv_path = os.path.join(project_root, "sim/verification/source/scenarios.csv")
    mem_path = os.path.join(project_root, "sim/verification/source/stimulus.mem")
    report_csv_path = os.path.join(current_dir, "verification_report.csv")

    initial_mem_state = load_stimulus_mem(mem_path)  # 수정된 로더 호출
    G, R, C, W = "\033[92m", "\033[91m", "\033[96m", "\033[0m"
    full_log_data = []

    with open(csv_path, 'r') as f:
        reader = list(csv.DictReader(f))
        for row in reader:
            tid, src, dst, length = row['id'], int(row['src_addr'], 16), int(row['dst_addr'], 16), int(row['length'])

            # CSV에서 정답 라벨(word_0 ~ word_15) 가져오기 [cite: 2]
            expected_vals = []
            for i in range(16):
                val_hex = row.get(f'word_{i}', '0x0')
                expected_vals.append(int(val_hex, 16))

            dma = TopDMA()  #
            dma.reg_src_addr, dma.reg_dst_addr, dma.reg_length, dma.reg_start = src, dst, length, 1
            slave = Improved_AXI_Slave(initial_mem_state)

            for cycle in range(1000):  # 64B 전송 루프
                arlen_input = dma.rm.get_current_arlen()
                s_arready, s_rvalid, s_rlast, s_rdata = slave.handle_axi_read(
                    dma.rm.arvalid, dma.rm.current_addr, arlen_input, not dma.fifo.full
                )
                out = dma.step(s_arready, s_rvalid, s_rlast, s_rdata, 1, 1, 1)
                dma.reg_start = 0
                slave.handle_axi_write(out['wm']['awvalid'], out['wm']['awaddr'], out['wm']['wvalid'],
                                       out['wm']['wdata'])
                if out['status'] == 1: break

            print(f"\n{C}📂 TEST ID: {tid} | 64B Burst 전송 상세 (전수 조사){W}")  #
            print(f" {'─' * 85}")
            print(f" {'SOURCE ADDR':<12} : {'LABEL DATA':<10}  ==>  {'DEST ADDR':<12} : {'RESULT':<10} | {'STATUS'}")
            print(f" {'─' * 12} : {'─' * 10}       {'─' * 12} : {'─' * 10} | {'─' * 6}")

            mismatch_count = 0
            for i in range(0, length, 4):
                s_addr, d_addr = src + i, dst + i
                label_val = expected_vals[i // 4]
                result_val = slave.mem.get(d_addr, 0)

                status = "OK" if label_val == result_val else "FAIL"
                if status == "FAIL": mismatch_count += 1

                color = G if status == "OK" else R
                print(
                    f" {hex(s_addr):<12} : 0x{label_val:08x}  ==>  {hex(d_addr):<12} : 0x{result_val:08x} | {color}{status}{W}")  #

                full_log_data.append({
                    "Test_ID": tid, "Source_Addr": hex(s_addr), "Label_Data": f"0x{label_val:08x}",
                    "Dest_Addr": hex(d_addr), "Dest_Data": f"0x{result_val:08x}", "Status": status
                })
            print(f" {'─' * 85}")

    # CSV 파일 저장 로직 (기존 유지)
    if full_log_data:
        keys = full_log_data[0].keys()
        with open(report_csv_path, 'w', newline='', encoding='utf-8') as output_file:
            dict_writer = csv.DictWriter(output_file, fieldnames=keys)
            dict_writer.writeheader()
            dict_writer.writerows(full_log_data)
        print(f"💾 {C}결과 저장 완료: {report_csv_path}{W}")


if __name__ == "__main__":
    run_total_verification()