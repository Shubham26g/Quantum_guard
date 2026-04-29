`timescale 1ns/1ps
 
module tb_compute_layer;
 
    reg        clk = 0;
    reg        rst = 1;
    reg        start = 0;
    reg  [7:0] c_tilde_0;
    reg  [7:0] mu_0;
    wire       done;
    wire       valid;
 
    always #5 clk = ~clk;
 
    compute_layer dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .c_tilde_0 (c_tilde_0),
        .mu_0      (mu_0),
        .done      (done),
        .valid     (valid)
    );
 
    localparam [7:0] EXPECTED_C_TILDE_0 = 8'h25;
    localparam [7:0] EXPECTED_MU_0      = 8'h28;
 
    integer i;
 
    task run_test;
        input [7:0] ct0;
        input [7:0] m0;
        input       expect_valid;
        reg         found;
        begin
            found = 0;
            @(posedge clk);
            c_tilde_0 <= ct0;
            mu_0      <= m0;
            start     <= 1;
            @(posedge clk);
            start <= 0;
 
            for (i = 0; i < 400; i = i + 1) begin
                @(posedge clk);
                if (done && !found) begin
                    found = 1;
                    if (valid === expect_valid)
                        $display("PASS: valid=%b (expected %b)", valid, expect_valid);
                    else
                        $display("FAIL: valid=%b (expected %b)", valid, expect_valid);
                end
            end
 
            if (!found)
                $display("TIMEOUT: done never asserted");
 
            repeat(10) @(posedge clk);
        end
    endtask
 
    initial begin
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);
 
        $display("=== TEST 1: Valid ===");
        run_test(EXPECTED_C_TILDE_0, EXPECTED_MU_0, 1'b1);
 
        $display("=== TEST 2: Forged c_tilde ===");
        run_test(EXPECTED_C_TILDE_0 ^ 8'h01, EXPECTED_MU_0, 1'b0);
 
        $display("=== TEST 3: Wrong mu_0 ===");
        run_test(EXPECTED_C_TILDE_0, EXPECTED_MU_0 ^ 8'hFF, 1'b0);
 
        $display("=== DONE ===");
        $finish;
    end
 
    initial begin
        #200_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end
 
endmodule