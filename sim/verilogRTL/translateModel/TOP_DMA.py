"""
파일명: TOP_DMA.py
설명: 전체 모듈을 하나로 묶는 최상위 래퍼 (Import 수정 완료)
"""
# 점(.)을 빼고 전체 패키지 경로를 다 적어버립니다.
from sim.verilogRTL.translateModel.FIFO import FIFO
from sim.verilogRTL.translateModel.readMasterVerilog import ReadMaster
from sim.verilogRTL.translateModel.writeMasterVerilog import WriteMaster


class TopDMA:
    def __init__(self):
        self.rm = ReadMaster()
        self.wm = WriteMaster()
        self.fifo = FIFO(depth=1024)

        # 레지스터 (CPU가 건드리는 변수들)
        self.reg_start = 0  # 시작 신호
        self.reg_status = 0  # 완료 신호 (1=Done)
        self.reg_src_addr = 0
        self.reg_dst_addr = 0
        self.reg_length = 0

        # 내부 로직용: Rising Edge 검출을 위한 이전 상태 저장
        self.prev_start_reg = 0

    def step(self, arready, rvalid, rlast, rdata, awready, wready, bvalid):
        # 1. Start 신호 Pulse 변환 (Level -> Pulse)
        # CPU가 1을 계속 누르고 있어도, 내부적으로는 딱 1클럭만 '탁' 튀게 만듦
        i_start_pulse = 0
        if self.reg_start == 1 and self.prev_start_reg == 0:
            i_start_pulse = 1

        self.prev_start_reg = self.reg_start  # 상태 업데이트

        # 2. Read Master 실행
        # (Top에서는 Slave가 주는 신호들을 RM에게 전달)
        rm_out = self.rm.step(
            i_start_pulse, self.reg_src_addr, self.reg_length, self.fifo.full,
            arready, rvalid, rlast, rdata
        )

        # RM이 데이터를 뱉으면 FIFO에 넣음
        if rm_out['push']:
            self.fifo.push(rm_out['data'])

        # 3. Write Master 실행
        # (WM은 FIFO 상태를 보고 동작)
        wm_out = self.wm.step(
            i_start_pulse, self.reg_dst_addr, self.reg_length, self.fifo.empty, self.fifo.peek(),
            awready, wready, bvalid
        )

        # WM이 데이터를 가져가면 FIFO에서 뺌
        if wm_out['pop']:
            self.fifo.pop()

        # 4. 전체 완료 체크 (둘 다 Done이면 Status 레지스터 1로 설정)
        if rm_out['done'] and wm_out['done']:
            self.reg_status = 1
            self.reg_start = 0  # 하드웨어처럼 Start 비트 자동 클리어

        # 외부(Testbench)에서 볼 수 있게 상태 리턴
        return {
            'rm': rm_out,
            'wm': wm_out,
            'fifo_cnt': self.fifo.count,
            'status': self.reg_status
        }