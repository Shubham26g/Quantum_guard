// ============================================================
// Module 3: tb_packet_receiver.v — Testbench
//
// Clock: 100MHz (10ns period)
// Baud: 115200 → bit period = 868 cycles = 8680ns
//
// Reads packet.hex (one byte per line, uppercase hex, no prefix)
// Sends full packet over simulated UART RX line
// Checks: msg_len, sig_len, pkt_valid, first/last msg & sig bytes
// ============================================================
 
`timescale 1ns/1ps
 
module tb_packet_receiver;
 
// ---- Clock ----
reg clk = 0;
always #5 clk = ~clk;  // 100MHz = 10ns period
 
reg rst = 1;
reg rx  = 1;           // UART idle = HIGH
 
// ---- DUT ----
wire        pkt_valid;
wire [11:0] msg_len;
wire [11:0] sig_len;
wire [7:0]  msg     [0:255];
wire [7:0]  sig_out [0:2419];
 
packet_receiver #(
    .CLKS_PER_BIT(868),
    .MAX_MSG_LEN (256),
    .MAX_SIG_LEN (2420)
) dut (
    .clk      (clk),
    .rst      (rst),
    .rx       (rx),
    .pkt_valid(pkt_valid),
    .msg      (msg),
    .sig_out  (sig_out),
    .msg_len  (msg_len),
    .sig_len  (sig_len)
);
 
// ---- Packet memory ----
// ML-DSA-44 packet max size:
// 1 + 2 + 15 + 2 + 2420 + 1 = 2441 bytes (for "HELLO FPGA TEST")
reg [7:0] pkt_mem [0:2500];
integer   pkt_size;
integer   i;
 
// ---- UART byte send task ----
// Bit period = 868 cycles * 10ns = 8680ns
localparam integer BIT_PERIOD = 8680; // ns
 
task send_byte;
    input [7:0] data;
    integer b;
    begin
        // Start bit
        rx = 0;
        #(BIT_PERIOD);
 
        // 8 data bits, LSB first
        for (b = 0; b < 8; b = b + 1) begin
            rx = data[b];
            #(BIT_PERIOD);
        end
 
        // Stop bit
        rx = 1;
        #(BIT_PERIOD);
    end
endtask
 
// ---- Test ----
integer pass_count;
integer fail_count;
 
initial begin
    pass_count = 0;
    fail_count = 0;
 
    // Load hex file — must be in Vivado project directory
    // Format: one byte per line e.g. "AA"
    $readmemh("packet.hex", pkt_mem);
 
    // ML-DSA-44, message = "HELLO FPGA TEST" (15 bytes)
    // packet size = 1+2+15+2+2420+1 = 2441
    pkt_size = 2441;
 
    // Release reset after 5 cycles
    repeat(5) @(posedge clk);
    rst = 0;
    repeat(5) @(posedge clk);
 
    $display("==============================================");
    $display("TB: Starting UART packet transmission");
    $display("TB: Sending %0d bytes", pkt_size);
    $display("==============================================");
 
    // Send all bytes
    for (i = 0; i < pkt_size; i = i + 1) begin
        send_byte(pkt_mem[i]);
    end
 
    $display("TB: All bytes sent. Waiting for pkt_valid...");
 
    // Wait enough time for last byte to be processed
    // Stop bit + FSM processing = ~2 bit periods safe margin
    #(BIT_PERIOD * 3);
 
    // ---- Checks ----
    $display("");
    $display("--- RESULTS ---");
 
    // Check pkt_valid
    // Note: pkt_valid pulses 1 cycle; use @posedge or check within window
    // We use a small wait loop approach
    fork
        begin : wait_valid
            repeat(1000) @(posedge clk);
            $display("FAIL: pkt_valid never asserted");
            fail_count = fail_count + 1;
            disable wait_valid;
        end
        begin
            @(posedge pkt_valid);
            $display("PASS: pkt_valid asserted");
            pass_count = pass_count + 1;
            disable wait_valid;
        end
    join
 
    // Check msg_len (should be 15 for "HELLO FPGA TEST")
    if (msg_len == 12'd15) begin
        $display("PASS: msg_len = %0d", msg_len);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: msg_len = %0d (expected 15)", msg_len);
        fail_count = fail_count + 1;
    end
 
    // Check sig_len (ML-DSA-44 = 2420 bytes)
    if (sig_len == 12'd2420) begin
        $display("PASS: sig_len = %0d", sig_len);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: sig_len = %0d (expected 2420)", sig_len);
        fail_count = fail_count + 1;
    end
 
    // Check first message byte = 'H' = 0x48
    if (msg[0] == 8'h48) begin
        $display("PASS: msg[0] = 0x%02X ('H')", msg[0]);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: msg[0] = 0x%02X (expected 0x48)", msg[0]);
        fail_count = fail_count + 1;
    end
 
    // Check last message byte = 'T' = 0x54
    if (msg[14] == 8'h54) begin
        $display("PASS: msg[14] = 0x%02X ('T')", msg[14]);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: msg[14] = 0x%02X (expected 0x54)", msg[14]);
        fail_count = fail_count + 1;
    end
 
    // Check sig[0] = first byte of signature = c_tilde[0]
    // This value comes from your packet.hex — print it to verify
    $display("INFO: sig_out[0] = 0x%02X (check against Python c_tilde[0])", sig_out[0]);
    $display("INFO: sig_out[1] = 0x%02X", sig_out[1]);
 
    $display("");
    $display("==============================================");
    $display("PASSED: %0d | FAILED: %0d", pass_count, fail_count);
    $display("==============================================");
 
    $finish;
end
 
// ---- Timeout watchdog ----
// Full packet at 115200 baud = 2441 bytes * ~96us = ~234ms
// At 100MHz sim = 23,400,000 cycles. Add margin.
initial begin
    #300_000_000; // 300ms sim time
    $display("TIMEOUT: Simulation exceeded 300ms");
    $finish;
end
 
// ---- Optional waveform dump ----
initial begin
    $dumpfile("uart_sim.vcd");
    $dumpvars(0, tb_packet_receiver);
end
 
endmodule