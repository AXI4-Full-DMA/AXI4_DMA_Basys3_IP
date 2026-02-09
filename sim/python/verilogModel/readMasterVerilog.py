class ReadMaster:
    """
    [RTL 대응: Read_Master.v]
    - Fix: 'get_current_arlen()' 추가로 Slave에게 정확한 버스트 길이를 전달
    """
    IDLE = 0
    ADDR_PHASE = 1
    DATA_PHASE = 2

    def __init__(self):
        self.state = self.IDLE
        self.current_addr = 0
        self.remaining_bytes = 0
        self.burst_len = 0
        self.arvalid = 0
        self.read_done = 0

    def get_current_arlen(self):
        """
        [Helper] 현재 상태에서 Slave에게 보내야 할 Burst Length (N-1) 계산
        - ADDR_PHASE일 때 올바른 길이를 미리 계산해서 리턴
        """
        if self.state == self.ADDR_PHASE or (self.state == self.IDLE and self.remaining_bytes > 0):
            # RTL 로직과 동일한 계산
            next_4kb = 0x1000 - (self.current_addr & 0xFFF)
            max_burst = 16 * 4  # 64 Bytes
            calc_len = min(self.remaining_bytes, next_4kb, max_burst)
            beats = calc_len // 4
            return (beats - 1) if beats > 0 else 0

        # 이미 계산된 burst_len이 있다면 그것을 사용
        return (self.burst_len - 1) if self.burst_len > 0 else 0

    def step(self, i_start, i_src_addr, i_total_len, i_fifo_full, m_axi_arready, m_axi_rvalid, m_axi_rlast,
             m_axi_rdata):
        # 1. 조합 로직: 길이 계산
        next_4kb = 0x1000 - (self.current_addr & 0xFFF)
        max_burst = 16 * 4
        calc_len = min(self.remaining_bytes, next_4kb, max_burst)

        next_state = self.state
        fifo_push = False

        # 2. FSM
        if self.state == self.IDLE:
            if i_start:
                self.current_addr = i_src_addr
                self.remaining_bytes = i_total_len
                self.read_done = 0
                self.arvalid = 1
                next_state = self.ADDR_PHASE

        elif self.state == self.ADDR_PHASE:
            if self.arvalid and m_axi_arready:  # Handshake
                self.burst_len = calc_len // 4  # 여기서 내부 레지스터 업데이트
                self.arvalid = 0
                next_state = self.DATA_PHASE
            else:
                self.arvalid = 1

        elif self.state == self.DATA_PHASE:
            m_axi_rready = not i_fifo_full

            if m_axi_rvalid and m_axi_rready:
                fifo_push = True
                if m_axi_rlast:
                    bytes_transferred = self.burst_len * 4
                    self.current_addr += bytes_transferred
                    self.remaining_bytes -= bytes_transferred

                    if self.remaining_bytes <= 0:
                        next_state = self.IDLE
                        self.read_done = 1
                    else:
                        next_state = self.ADDR_PHASE
                        self.arvalid = 1

        self.state = next_state

        # Output에 get_current_arlen() 값을 사용해 일관성 유지
        return {
            'araddr': self.current_addr,
            'arlen': self.get_current_arlen(),
            'arvalid': self.arvalid,
            'push': fifo_push,
            'data': m_axi_rdata,
            'done': self.read_done
        }