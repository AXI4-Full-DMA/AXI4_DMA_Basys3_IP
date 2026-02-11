class WriteMaster:
    """
    [RTL 대응: Write_Master.v]
    - AXI Write Channel 제어
    - FIFO Pop 제어
    """
    IDLE = 0
    AW_PHASE = 1
    W_PHASE = 2
    B_PHASE = 3

    def __init__(self):
        # Registers
        self.state = self.IDLE
        self.current_addr = 0
        self.remaining_bytes = 0
        self.burst_len = 0
        self.beat_cnt = 0
        self.write_done = 0

    def step(self, i_start, i_dst_addr, i_total_len, i_fifo_empty, i_fifo_data, m_axi_awready, m_axi_wready,
             m_axi_bvalid):
        # -----------------------------------------------------------
        # 1. Combinational Logic
        # -----------------------------------------------------------
        next_4kb = 0x1000 - (self.current_addr & 0xFFF)
        max_burst = 16 * 4
        calc_len = min(self.remaining_bytes, next_4kb, max_burst)

        # Output Signals (Default)
        awvalid = 1 if self.state == self.AW_PHASE else 0
        wvalid = 1 if (self.state == self.W_PHASE and not i_fifo_empty) else 0
        wlast = 1 if (self.state == self.W_PHASE and self.beat_cnt == self.burst_len - 1) else 0

        fifo_pop = False
        next_state = self.state

        # -----------------------------------------------------------
        # 2. Sequential Logic (FSM)
        # -----------------------------------------------------------
        if self.state == self.IDLE:
            if i_start:
                self.current_addr = i_dst_addr
                self.remaining_bytes = i_total_len
                self.write_done = 0
                next_state = self.AW_PHASE

        elif self.state == self.AW_PHASE:
            if awvalid and m_axi_awready:
                self.burst_len = calc_len // 4
                self.beat_cnt = 0
                next_state = self.W_PHASE

        elif self.state == self.W_PHASE:
            if wvalid and m_axi_wready:
                fifo_pop = True  # 전송 성공 시 FIFO Pop
                if wlast:
                    next_state = self.B_PHASE
                else:
                    self.beat_cnt += 1

        elif self.state == self.B_PHASE:
            if m_axi_bvalid:  # Write Response 수신
                # 주소 업데이트
                bytes_transferred = self.burst_len * 4
                self.current_addr += bytes_transferred
                self.remaining_bytes -= bytes_transferred

                if self.remaining_bytes <= 0:
                    next_state = self.IDLE
                    self.write_done = 1
                else:
                    next_state = self.AW_PHASE

        # 상태 업데이트
        self.state = next_state

        return {
            'awaddr': self.current_addr,
            'awlen': (self.burst_len - 1) if self.burst_len > 0 else 0,
            'awvalid': awvalid,
            'wdata': i_fifo_data,
            'wlast': wlast,
            'wvalid': wvalid,
            'pop': fifo_pop,
            'done': self.write_done
        }