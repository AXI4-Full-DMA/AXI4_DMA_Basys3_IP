`timescale 1ns / 1ps

module Read_Master # (
    parameter integer C_M_AXI_ID_WIDTH   = 1,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset_n,

    // Control Signals
    input wire i_start,
    input wire [31:0] i_src_addr,
    input wire [31:0] i_total_len,
    output reg o_read_done,

    // FIFO Interface
    input wire i_fifo_full,
    output wire o_fifo_push,
    output wire [31:0] o_r_data,

    // AXI4-Full Master (AR Channel)
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_araddr,
    output wire [7 : 0] m_axi_arlen,
    output wire [2 : 0] m_axi_arsize,
    output wire [1 : 0] m_axi_arburst,
    output wire m_axi_arvalid,         // [수정] reg 연결 (via assign)
    input  wire m_axi_arready,

    // AXI4-Full Master (R Channel)
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_rdata,
    input  wire m_axi_rlast,
    input  wire m_axi_rvalid,
    output wire m_axi_rready
);

    // FSM States
    localparam IDLE       = 3'b001;
    localparam ADDR_PHASE = 3'b010;
    localparam DATA_PHASE = 3'b100;

    reg [2:0] current_state;
    reg [2:0] next_state;

    // Registers
    reg [31:0] r_current_addr;
    reg [31:0] r_remaining_bytes;
    reg [7:0]  r_burst_len;
    reg        arvalid_reg; // [추가] ARVALID 제어용 레지스터

    // Calculation Wires
    wire [31:0] next_boundary_addr;
    wire [31:0] dist_to_boundary;
    wire [31:0] max_burst_bytes;
    wire [31:0] calc_len_bytes;
    wire [31:0] current_transfer_bytes;

    // -------------------------------------------------------------------------
    // 1. Calculations
    // -------------------------------------------------------------------------
    assign next_boundary_addr = (r_current_addr & 32'hFFFF_F000) + 32'h1000;
    assign dist_to_boundary   = next_boundary_addr - r_current_addr;
    assign max_burst_bytes    = (r_remaining_bytes > 256) ? 256 : r_remaining_bytes;
    assign calc_len_bytes     = (max_burst_bytes > dist_to_boundary) ? dist_to_boundary : max_burst_bytes;
    
    assign current_transfer_bytes = {22'd0, r_burst_len, 2'b00}; // r_burst_len * 4

    // -------------------------------------------------------------------------
    // 2. AXI Output Assignments
    // -------------------------------------------------------------------------
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_araddr  = r_current_addr;
    
    // [수정] 레지스터 값을 출력으로 연결
    assign m_axi_arvalid = arvalid_reg; 
    
    assign m_axi_arlen   = (calc_len_bytes[9:2] > 0) ? (calc_len_bytes[9:2] - 1) : 0;
    assign m_axi_rready  = (current_state == DATA_PHASE) && (!i_fifo_full);

    // -------------------------------------------------------------------------
    // 3. FIFO Output
    // -------------------------------------------------------------------------
    assign o_fifo_push = (m_axi_rvalid && m_axi_rready);
    assign o_r_data    = m_axi_rdata;

    // -------------------------------------------------------------------------
    // 4. Next State Logic
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (i_start) next_state = ADDR_PHASE;
            end
            ADDR_PHASE: begin
                // ARVALID는 별도 레지스터로 제어하지만, 상태 천이는 여전히 Handshake 기준
                if (m_axi_arvalid && m_axi_arready) 
                    next_state = DATA_PHASE;
            end
            DATA_PHASE: begin
                if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                    if (r_remaining_bytes <= current_transfer_bytes)
                        next_state = IDLE;
                    else
                        next_state = ADDR_PHASE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // 5. ARVALID Control Logic (User Suggested) - [추가됨]
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            arvalid_reg <= 0;
        else begin
            case (current_state)
                IDLE: begin
                    // 시작 신호가 오면 바로 High로 띄움 (Ready to go)
                    if (i_start) arvalid_reg <= 1;
                    else         arvalid_reg <= 0;
                end

                ADDR_PHASE: begin
                    // Handshake(Ready=1)가 오면 즉시 Low로 떨어짐 (Self-clearing)
                    // Ready가 안 오면 High 유지
                    if (arvalid_reg && m_axi_arready)
                        arvalid_reg <= 0;
                end

                DATA_PHASE: begin
                    // 마지막 데이터를 받는 순간, 남은 데이터가 있다면 미리 Valid를 띄움 (Look-ahead)
                    if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                        if (r_remaining_bytes > current_transfer_bytes)
                            arvalid_reg <= 1; // Look-ahead: next_state와 동시에 적용되어 ADDR_PHASE 진입 시 arvalid가 이미 High
                        else
                            arvalid_reg <= 0;
                    end
                end
                
                default: arvalid_reg <= 0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 6. State Machine & Register Update
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state     <= IDLE;
            r_current_addr    <= 0;
            r_remaining_bytes <= 0;
            r_burst_len       <= 0;
            o_read_done       <= 0;
        end else begin
            current_state <= next_state;

            case (current_state)
                IDLE: begin
                    if (i_start) begin
                        o_read_done <= 0;
                        r_current_addr    <= i_src_addr;
                        r_remaining_bytes <= i_total_len;
                    end
                end

                ADDR_PHASE: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        r_burst_len <= calc_len_bytes[9:2];
                    end
                end

                DATA_PHASE: begin
                    if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                        r_current_addr <= r_current_addr + current_transfer_bytes;
                        
                        if (r_remaining_bytes > current_transfer_bytes)
                            r_remaining_bytes <= r_remaining_bytes - current_transfer_bytes;
                        else begin
                            r_remaining_bytes <= 0;
                            o_read_done       <= 1;
                        end
                    end
                end
            endcase
        end
    end
endmodule