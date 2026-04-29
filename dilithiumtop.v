// =============================================================================
// Module  : dilithium_top
// Purpose : Full pipeline integration
//
// Pipeline:
//   uart_rx → packet_receiver → compute_layer → LED output
//
// Connections:
//   pkt_valid  → start
//   sig[0]     → c_tilde_0
//   mu_0       → hardcoded from mu.hex[0] (set after running Python)
//
// LED:
//   led[0] = GREEN (valid signature)
//   led[1] = RED   (invalid/forged)
// =============================================================================
 
 `timescale 1ns/1ps


module dilithium_top (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,         // UART RX pin
    output wire [1:0] led         // led[0]=GREEN led[1]=RED
);
 
    // -------------------------------------------------------------------------
    // Block 1+2: Packet receiver
    // -------------------------------------------------------------------------
    wire        pkt_valid;
    wire [11:0] msg_len;
    wire [11:0] sig_len;

    wire [7:0] c_tilde_0;

    packet_receiver #(
        .CLKS_PER_BIT (868),
        .MAX_MSG_LEN  (256),
        .MAX_SIG_LEN  (2420)
    ) u_pkt (
        .clk      (clk),
        .rst      (rst),
        .rx       (rx),
        .pkt_valid(pkt_valid),
        .msg_len  (msg_len),
        .sig_len  (sig_len),
        .sig_byte0 (c_tilde_0)
    );
 
    // -------------------------------------------------------------------------
    // c_tilde[0] extraction — sig_out[0] per packet format
    // -------------------------------------------------------------------------
 
    // -------------------------------------------------------------------------
    // mu[0] — hardcoded after running Python script
    // Run script, read mu.hex line 1, paste hex value here
    // Example: if mu.hex line 1 = "A3", set 8'hA3
    // -------------------------------------------------------------------------
    wire [7:0] mu_0 = 8'h28;
 
    // -------------------------------------------------------------------------
    // Block 3: Compute layer
    // -------------------------------------------------------------------------
    wire compute_done;
    wire compute_valid;
 
    compute_layer u_compute (
        .clk       (clk),
        .rst       (rst),
        .start     (pkt_valid),
        .c_tilde_0 (c_tilde_0),
        .mu_0      (mu_0),
        .done      (compute_done),
        .valid     (compute_valid)
    );
 
    // -------------------------------------------------------------------------
    // Block 4: LED output — latch on done pulse
    // -------------------------------------------------------------------------
    reg led_green = 0;
    reg led_red   = 0;
 
    always @(posedge clk) begin
        if (rst) begin
            led_green <= 0;
            led_red   <= 0;
        end else if (compute_done) begin
            led_green <= compute_valid;
            led_red   <= ~compute_valid;
        end
    end
 
    assign led[0] = led_green;
    assign led[1] = led_red;
 
endmodule