`timescale 1ns/1ps
 
module tb_full_pipeline;
 
    reg clk = 0;
    reg rst = 1;
    reg rx  = 1;
 
    always #5 clk = ~clk; // 100MHz clock
 
    // LED outputs
    wire [1:0] led;
 
    // DUT — full pipeline
    dilithium_top dut (
        .clk (clk),
        .rst (rst),
        .rx  (rx),
        .led (led)
    );
 
    // Packet memory
    reg [7:0] pkt_mem [0:2500];
    integer i;
 
    // UART send task — 115200 baud, 8N1
    localparam integer BIT_PERIOD = 8680; // ns
 
    task send_byte;
        input [7:0] data;
        integer b;
        begin
            rx = 0; #(BIT_PERIOD);
            for (b = 0; b < 8; b = b + 1) begin
                rx = data[b]; #(BIT_PERIOD);
            end
            rx = 1; #(BIT_PERIOD);
        end
    endtask
    /*
    initial begin
        $readmemh("packet.hex", pkt_mem);
 
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);
 
        $display("=== Sending packet over UART ===");
 
        // ML-DSA-44, "HELLO FPGA TEST" = 2441 bytes
        for (i = 0; i < 2441; i = i + 1)
            send_byte(pkt_mem[i]);
 
        $display("=== Packet sent. Waiting for result ===");
 
        // Wait for compute_layer to finish (~260 cycles after pkt_valid)
        repeat(500) @(posedge clk);
 
        $display("LED green=%b red=%b", led[0], led[1]);
 
        if (led[0] === 1'b1)
            $display("PASS: Valid signature — GREEN LED");
        else
            $display("FAIL: Expected GREEN, got RED");
 
        $finish;
    end
    */

    initial begin
        $readmemh("packet.hex", pkt_mem);

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        // === TEST 1: Valid ===
        $display("=== TEST 1: Valid signature ===");
        for (i = 0; i < 2441; i = i + 1)
            send_byte(pkt_mem[i]);
        repeat(2000) @(posedge clk);
        $display("LED green=%b red=%b", led[0], led[1]);
        if (led[0] === 1'b1) 
            $display("PASS: GREEN");
        else                 
            $display("FAIL: expected GREEN");

        repeat(100) @(posedge clk);
        rst = 1; 
        repeat(5) @(posedge clk); 
        rst = 0; // reset between tests

        // === TEST 2: Forged signature ===
        $display("=== TEST 2: Forged signature ===");
        pkt_mem[20] = pkt_mem[20] ^ 8'hFF; // corrupt byte inside signature
        for (i = 0; i < 2441; i = i + 1)
            send_byte(pkt_mem[i]);
        repeat(2000) @(posedge clk);
        $display("LED green=%b red=%b", led[0], led[1]);
        if (led[1] === 1'b1) 
            $display("PASS: RED — forgery detected");
        else   
            $display("FAIL: expected RED");

        $display("=== ALL DONE ===");
        $finish;
    end
 
    // Watchdog — full packet ~212ms + margin
    initial begin
        #600_000_000;
        $display("TIMEOUT");
        $finish;
    end
 
endmodule