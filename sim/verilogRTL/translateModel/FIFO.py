class FIFO:
    """
    [RTL 대응: fifo_generator_0]
    - Depth: 1024 (4KB)
    - Width: 32-bit
    - Type: Common Clock Built-in FIFO
    """
    def __init__(self, depth=1024):
        self.depth = depth
        self.memory = [0] * depth
        self.wr_ptr = 0
        self.rd_ptr = 0
        self.count = 0

    @property
    def full(self):
        return self.count == self.depth

    @property
    def empty(self):
        return self.count == 0

    def push(self, data):
        """데이터 쓰기 (RTL: wr_en & !full)"""
        if not self.full:
            self.memory[self.wr_ptr] = data
            self.wr_ptr = (self.wr_ptr + 1) % self.depth
            self.count += 1
            return True
        return False

    def pop(self):
        """데이터 읽기 (RTL: rd_en & !empty)"""
        if not self.empty:
            data = self.memory[self.rd_ptr]
            self.rd_ptr = (self.rd_ptr + 1) % self.depth
            self.count -= 1
            return data
        return None

    def peek(self):
        """데이터 확인 (RTL: dout)"""
        return self.memory[self.rd_ptr] if not self.empty else 0