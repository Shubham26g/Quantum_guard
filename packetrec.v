// ============================================================
// Module 2: packet_receiver.v — Packet Buffer & Assembler
//
// Packet format from Python script:
// [0xAA][MSG_LEN 2B BE][MESSAGE][SIG_LEN 2B BE][SIGNATURE][0xBB]
//
// ML-DSA-44 (Dilithium2):
//   Signature = 2420 bytes
//   Max message = 255 bytes (safe assumption)
//   Total max packet = 1+2+255+2+2420+1 = 2681 bytes
//
// Outputs msg[], sig[], msg_len, sig_len, pkt_valid
// pkt_valid pulses 1 cycle when full valid packet received
// ============================================================
 
module packet_receiver #(
    parameter CLKS_PER_BIT = 868, // 115200 baud at 100MHz
    parameter MAX_MSG_LEN  = 256,
    parameter MAX_SIG_LEN  = 2420
)(
    input            clk,
    input            rst,
    input            rx,
 
    output reg        pkt_valid,
    output reg [11:0] msg_len,   // up to 4095
    output reg [11:0] sig_len,    // up to 4095
    output reg [7:0] sig_byte0
    
);
 
// ---- UART instance ----
wire       rx_done;
wire [7:0] rx_byte;
 
uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_inst (
    .clk     (clk),
    .rst     (rst),
    .rx      (rx),
    .rx_done (rx_done),
    .rx_byte (rx_byte)
);
 
// ---- FSM ----
localparam S_IDLE   = 3'd0;
localparam S_MSGLEN = 3'd1;   // receive 2 bytes of msg length
localparam S_MSG    = 3'd2;   // receive message bytes
localparam S_SIGLEN = 3'd3;   // receive 2 bytes of sig length
localparam S_SIG    = 3'd4;   // receive signature bytes
localparam S_END    = 3'd5;   // expect 0xBB

reg [7:0] msg     [0:MAX_MSG_LEN-1];
reg [7:0] sig_out [0:MAX_SIG_LEN-1];
 
reg [2:0]  state = S_IDLE;
reg [11:0] cnt   = 0;         // 12-bit: handles up to 4095 bytes
reg [7:0]  first_len_byte;    // stores high byte of length field
 
always @(posedge clk) begin
    if (rst) begin
        state     <= S_IDLE;
        cnt       <= 0;
        pkt_valid <= 0;
        msg_len   <= 0;
        sig_len   <= 0;
        sig_byte0 <= 0;
    end else begin
        pkt_valid <= 0; // default
 
        if (rx_done) begin
            case (state)
 
                S_IDLE: begin
                    cnt <= 0;
                    if (rx_byte == 8'hAA)
                        state <= S_MSGLEN;
                    // ignore any other byte — stay idle
                end
 
                S_MSGLEN: begin
                    if (cnt == 0) begin
                        first_len_byte <= rx_byte; // store high byte
                        cnt <= 1;
                    end else begin
                        msg_len <= {first_len_byte, rx_byte}; // big-endian
                        cnt     <= 0;
                        state   <= S_MSG;
                    end
                end
 
                S_MSG: begin
                    if (msg_len == 0) begin
                        // zero-length message: skip straight to sig length
                        cnt   <= 0;
                        state <= S_SIGLEN;
                    end else begin
                        if (cnt < MAX_MSG_LEN)
                            msg[cnt] <= rx_byte;
                        if (cnt == msg_len - 1) begin
                            cnt   <= 0;
                            state <= S_SIGLEN;
                        end else
                            cnt <= cnt + 1;
                    end
                end
 
                S_SIGLEN: begin
                    if (cnt == 0) begin
                        first_len_byte <= rx_byte;
                        cnt <= 1;
                    end else begin
                        sig_len <= {first_len_byte, rx_byte};
                        cnt     <= 0;
                        state   <= S_SIG;
                    end
                end
 
                S_SIG: begin
                    if (cnt == 0) 
                        sig_byte0 <= rx_byte;
                    if (cnt < MAX_SIG_LEN) 
                        sig_out[cnt] <= rx_byte;
                    if (cnt == sig_len - 1) begin
                        cnt   <= 0;
                        state <= S_END;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
 
                S_END: begin
                    if (rx_byte == 8'hBB)
                        pkt_valid <= 1;  // valid packet complete
                    // if wrong end byte: silently reset, don't assert valid
                    state <= S_IDLE;
                end
 
                default: state <= S_IDLE;
 
            endcase
        end
    end
end
 
endmodule