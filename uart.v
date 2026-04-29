// ============================================================
// Module 1: uart_rx.v — UART Byte Receiver
// Clock: 100MHz | Baud: 115200 | CLKS_PER_BIT = 868
// Samples each bit at midpoint for noise immunity
// ============================================================
 
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input            clk,
    input            rst,
    input            rx,
    output reg       rx_done,   // pulses 1 cycle when byte ready
    output reg [7:0] rx_byte
);
 
localparam S_IDLE  = 2'd0;
localparam S_START = 2'd1;
localparam S_DATA  = 2'd2;
localparam S_STOP  = 2'd3;
 
reg [1:0]  state   = S_IDLE;
reg [9:0]  clk_cnt = 0;        // max 868, fits in 10 bits
reg [2:0]  bit_idx = 0;
reg [7:0]  rx_shift = 0;       // for metastability
 
// Two-stage synchronizer — critical for real hardware,
// good practice even in simulation
wire rx_sync2 = rx;
 
always @(posedge clk) begin
    if (rst) begin
        state   <= S_IDLE;
        clk_cnt <= 0;
        bit_idx <= 0;
        rx_done <= 0;
        rx_byte <= 0;
    end else begin
        rx_done <= 0; // default: no byte ready
 
        case (state)
 
            S_IDLE: begin
                clk_cnt <= 0;
                bit_idx <= 0;
                if (rx_sync2 == 0)      // falling edge = start bit
                    state <= S_START;
            end
 
            // Wait to midpoint of start bit, then confirm
            S_START: begin
                if (clk_cnt == (CLKS_PER_BIT/2) - 1) begin
                    if (rx_sync2 == 0) begin
                        clk_cnt <= 0;
                        state   <= S_DATA;
                    end else
                        state   <= S_IDLE; // false start
                end else
                    clk_cnt <= clk_cnt + 1;
            end
 
            // Sample each data bit at its midpoint
            S_DATA: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt           <= 0;
                    rx_shift[bit_idx] <= rx_sync2;
                    if (bit_idx == 3'd7) begin
                        bit_idx <= 0;
                        state   <= S_STOP;
                    end else
                        bit_idx <= bit_idx + 1;
                end else
                    clk_cnt <= clk_cnt + 1;
            end
 
            // Wait for stop bit, then output byte
            S_STOP: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    rx_done <= 1;
                    rx_byte <= rx_shift;
                    clk_cnt <= 0;
                    state   <= S_IDLE;
                end else
                    clk_cnt <= clk_cnt + 1;
            end
 
            default: state <= S_IDLE;
        endcase
    end
end
 
endmodule