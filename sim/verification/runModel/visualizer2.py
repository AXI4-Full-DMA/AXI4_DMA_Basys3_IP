import sys
import os
import matplotlib.pyplot as plt

# [1] 경로 설정 (TOP_DMA 내부의 패키지 임포트 구조 대응)
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "../../../"))
sys.path.append(project_root)

# [2] 모듈 임포트
try:
    from sim.verilogRTL.translateModel.TOP_DMA import TopDMA
    from verification import Improved_AXI_Slave
except ImportError as e:
    print(f"❌ 임포트 실패: {e}\n프로젝트 루트 경로를 확인하세요: {project_root}")
    sys.exit(1)

# 터미널 컬러 및 스타일
C, G, R, Y, W = "\033[96m", "\033[92m", "\033[91m", "\033[93m", "\033[0m"


class AXIDebugger:
    def __init__(self, clk_mhz=100):
        self.clk_mhz = clk_mhz
        self.records = []
        self.total_violations = 0

    def log_transaction(self, tid, size, cycles, addr_list):
        # 성능 계산
        speed = (size / cycles) * self.clk_mhz if cycles > 0 else 0

        # 4KB 경계 체크 (주소 리스트 전수 조사)
        is_safe = True
        violation_details = []
        for addr, burst_len in addr_list:
            end_addr = addr + (burst_len * 4) - 1
            if (addr >> 12) != (end_addr >> 12):
                is_safe = False
                violation_details.append(f"0x{addr:08X}")
                self.total_violations += 1

        self.records.append({
            'id': tid, 'size': size, 'cyc': cycles,
            'speed': speed, 'safe': is_safe, 'v_detail': violation_details
        })

    def print_final_report(self):
        print(f"\n{C}{'=' * 90}{W}")
        print(f"{C} AXI4 DMA PERFORMANCE & RULE CHECKER REPORT (Freq: {self.clk_mhz}MHz) {W}")
        print(f"{C}{'=' * 90}{W}")
        header = f"| {'ID':^4} | {'SIZE':^8} | {'CYCLES':^8} | {'SPEED(MB/s)':^12} | {'4KB RULE':^10} | {'REMARK':^20} |"
        print(header)
        print("-" * len(header))

        for r in self.records:
            status = f"{G}PASS{W}" if r['safe'] else f"{R}FAIL{W}"
            remark = ",".join(r['v_detail']) if not r['safe'] else "Valid Burst"
            print(
                f"| {r['id']:^4} | {r['size']:>6} B | {r['cyc']:>8} | {r['speed']:>12.2f} | {status:^19} | {remark:<20} |")

        print(f"{C}{'=' * 90}{W}")
        if self.total_violations == 0:
            print(f"{G}✅ 모든 전송이 AXI 4KB 경계 규격을 준수합니다. (Total Violations: 0){W}")
        else:
            print(f"{R}🚨 주의: {self.total_violations}건의 규격 위반이 발견되었습니다!{W}")


def run_sim():
    debugger = AXIDebugger(clk_mhz=100)
    # 테스트 시나리오 (사이즈 가변)
    test_cases = [
        {"id": 1, "size": 64, "src": 0xC0000000},
        {"id": 2, "size": 256, "src": 0xC0000FF0},  # 4KB 경계 걸침 유도
        {"id": 3, "size": 1024, "src": 0xC0001000},
        {"id": 4, "size": 4096, "src": 0xC0002F00}  # 대용량 및 경계 통과
    ]

    for tc in test_cases:
        dma = TopDMA()
        dma.reg_src_addr, dma.reg_dst_addr, dma.reg_length = tc['src'], 0xC2000000, tc['size']
        dma.reg_start = 1

        # 실제 데이터가 담긴 메모리 생성 (Improved_AXI_Slave 연동)
        initial_mem = {tc['src'] + i: i for i in range(0, tc['size'] + 64, 4)}
        slave = Improved_AXI_Slave(initial_mem)

        addr_trace = []  # (address, burst_len) 기록용
        total_cyc = 0

        for cyc in range(1, 10000):
            # 1. Read Master 주소 모니터링
            if dma.rm.arvalid and dma.rm.state == 1:  # ADDR_PHASE 일 때만
                addr_trace.append((dma.rm.current_addr, dma.rm.get_current_arlen() + 1))

            # 2. RTL Step 실행 (정확한 Slave 핸드쉐이크 공급)
            arlen_input = dma.rm.get_current_arlen()
            s_arready, s_rvalid, s_rlast, s_rdata = slave.handle_axi_read(
                dma.rm.arvalid, dma.rm.current_addr, arlen_input, not dma.fifo.full
            )

            # Write Master 주소 모니터링 및 Step
            out = dma.step(s_arready, s_rvalid, s_rlast, s_rdata, 1, 1, 1)

            if out['wm']['awvalid'] and dma.wm.state == 1:
                addr_trace.append((out['wm']['awaddr'], out['wm']['awlen'] + 1))

            slave.handle_axi_write(out['wm']['awvalid'], out['wm']['awaddr'], out['wm']['wvalid'], out['wm']['wdata'])

            if out['status'] == 1:
                total_cyc = cyc
                break

        debugger.log_transaction(tc['id'], tc['size'], total_cyc, addr_trace)

    debugger.print_final_report()

    # 성능 그래프 생성
    if debugger.records:
        plt.figure(figsize=(10, 5))
        ids = [str(r['id']) for r in debugger.records]
        speeds = [r['speed'] for r in debugger.records]
        plt.bar(ids, speeds, color='skyblue', edgecolor='navy')
        plt.title("AXI DMA Throughput by Test Case")
        plt.ylabel("Transfer Speed (MB/s)");
        plt.xlabel("Test ID")
        plt.grid(axis='y', linestyle='--', alpha=0.7)
        plt.savefig('dma_performance_bar.png')


if __name__ == "__main__":
    run_sim()