`timescale 1ns / 1ps

module Read_Master # (
    // AXI4-Full Parameters (변경 금지)
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32
)(
    // =========================================================================
    // 1. Global Signals
    // =========================================================================
    input wire clk,
    input wire reset_n,

    // =========================================================================
    // 2. Control Interface (Connected to Control_Slave)
    // =========================================================================
    input wire i_start,                // 동작 시작 트리거
    input wire [31:0] i_src_addr,      // 읽어올 시작 주소 (예: 0xC000_0000)
    input wire [31:0] i_total_len,     // 전송할 총 바이트 길이
    output reg o_read_done,            // 모든 읽기 완료 알림

    // =========================================================================
    // 3. FIFO Interface (Connected to Async FIFO)
    // =========================================================================
    input wire i_fifo_full,            // FIFO가 꽉 찼음 (1이면 읽기 중단)
    output reg o_fifo_push,            // FIFO에 데이터 넣기 (Write Enable)
    output reg [31:0] o_r_data,        // FIFO로 보낼 데이터

    // =========================================================================
    // 4. AXI4-Full Master Interface (Read Address Channel - AR)
    // =========================================================================
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_araddr,
    output wire [7 : 0] m_axi_arlen,   // Burst Length: 0=1 beat, 15=16 beats
    output wire [2 : 0] m_axi_arsize,  // Burst Size: 010=4bytes (32bit)
    output wire [1 : 0] m_axi_arburst, // Burst Type: 01=INCR (주소 증가)
    output wire m_axi_arlock,          // (Unused) Always 0
    output wire [3 : 0] m_axi_arcache, // (Unused) Always 0010
    output wire [2 : 0] m_axi_arprot,  // (Unused) Always 000
    output wire [3 : 0] m_axi_arqos,   // (Unused) Always 0000
    output reg  m_axi_arvalid,         // 주소 유효 신호
    input  wire m_axi_arready,         // Slave가 주소 받을 준비 됨

    // =========================================================================
    // 5. AXI4-Full Master Interface (Read Data Channel - R)
    // =========================================================================
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_rdata,
    input  wire [1 : 0] m_axi_rresp,   // (Unused) Response Status
    input  wire m_axi_rlast,           // Burst의 마지막 데이터임
    input  wire m_axi_rvalid,          // 데이터 유효 신호
    output reg  m_axi_rready           // Master가 데이터 받을 준비 됨
);

    // =========================================================================
    // [Internal Signals & Registers]
    // =========================================================================
    
    // FSM States
    localparam IDLE      = 3'b001;
    localparam ADDR_PHASE = 3'b010; // AR Channel Handshake
    localparam DATA_PHASE = 3'b100; // R Channel Handshake
    
    reg [2:0] current_state, next_state;

    // Internal Calculations
    reg [31:0] r_current_addr;    // 현재 읽고 있는 주소
    reg [31:0] r_remaining_bytes; // 남은 전송량
    reg [7:0]  r_burst_len;       // 이번 턴에 보낼 Burst 길이 (0~255)

    // =========================================================================
    // [AXI Constant Assignments]
    // =========================================================================
    assign m_axi_arsize  = 3'b010; // 4 Bytes (32-bit)
    assign m_axi_arburst = 2'b01;  // INCR Type
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0010;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    
    // ARADDR 연결: 현재 계산된 주소를 출력
    assign m_axi_araddr  = r_current_addr;
    // ARLEN 연결: 현재 계산된 Burst 길이 출력
    assign m_axi_arlen   = r_burst_len; 

    // =========================================================================
    // [Main FSM Logic]
    // =========================================================================
    
    // 1. State Transition
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) 
            current_state <= IDLE;
        else 
            current_state <= next_state;
    end

    // 2. Next State Logic (Combinational)
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (i_start) 
                    next_state = ADDR_PHASE;
                else
                    next_state = IDLE;
            end

            ADDR_PHASE: begin
                // TODO: ARVALID가 High이고 ARREADY가 들어오면(Handshake) 넘어감
                if (m_axi_arvalid && m_axi_arready)
                    next_state = DATA_PHASE;
            end

            DATA_PHASE: begin
                // TODO: RLAST(마지막 데이터)를 받고 Handshake가 끝나면
                if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                    if (r_remaining_bytes == 0) // 더 읽을 게 없으면
                         next_state = IDLE;     // 완료 (나중에 DONE 신호 발생)
                    else 
                         next_state = ADDR_PHASE; // 남은 게 있으면 다시 주소 전송
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // [Output Logic & Datapath]
    // =========================================================================
    
    // TODO: 팀원 3이 채워야 할 핵심 로직들
    
    // 1. r_current_addr 계산 로직
    // - i_start일 때 i_src_addr 로 초기화
    // - Burst가 끝날 때마다 읽은 만큼 주소 증가
    
    // 2. r_burst_len 계산 로직 (4KB Boundary 처리)
    // - 남은 길이가 16보다 크면 16으로 설정 (Max Burst 16)
    // - 4KB 경계에 걸리면 잘라서 보내기
    
    // 3. AXI Handshake 제어 (ARVALID, RREADY)
    // - ADDR_PHASE에서 ARVALID = 1
    // - DATA_PHASE에서 FIFO가 꽉 차지 않았으면(i_fifo_full == 0) RREADY = 1
    
    // 4. FIFO Push Logic
    // - RVALID && RREADY 일 때 o_fifo_push = 1, o_r_data = m_axi_rdata
    
    // 5. Done Signal
    // - 모든 전송이 끝나면 o_read_done = 1

endmodule
