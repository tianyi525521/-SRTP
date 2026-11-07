`timescale 1ns/1ps

module tb_srtp_controller_top;
  import srtp_types_pkg::*;

  localparam int unsigned NUM_REGIONS = 16;
  localparam int unsigned COUNT_W     = $clog2(NUM_REGIONS + 1);

  logic clk;
  logic rst_n;
  logic checkpoint_done;
  logic mem_write_valid;
  logic [31:0] mem_write_addr;
  logic [31:0] predicted_idle_cycles;
  logic [COUNT_W-1:0] modified_count;
  logic [31:0] checkpoint_cycles;
  logic [31:0] deep_threshold;
  sleep_mode_e sleep_mode;

  srtp_controller_top #(
    .NUM_REGIONS (NUM_REGIONS)
  ) dut (
    .clk_i                   (clk),
    .rst_ni                  (rst_n),
    .checkpoint_done_i       (checkpoint_done),
    .mem_write_valid_i       (mem_write_valid),
    .mem_write_addr_i        (mem_write_addr),
    .predicted_idle_cycles_i (predicted_idle_cycles),
    .modified_count_o        (modified_count),
    .checkpoint_cycles_o     (checkpoint_cycles),
    .deep_threshold_o        (deep_threshold),
    .sleep_mode_o            (sleep_mode)
  );

  always #5 clk = ~clk;

  task automatic write_address(input logic [31:0] addr);
    begin
      @(negedge clk);
      mem_write_valid = 1'b1;
      mem_write_addr  = addr;
      @(negedge clk);
      mem_write_valid = 1'b0;
    end
  endtask

  task automatic expect_count(input int unsigned expected);
    begin
      if (modified_count !== expected[COUNT_W-1:0]) begin
        $fatal(1, "modified_count=%0d, expected=%0d", modified_count, expected);
      end
    end
  endtask

  initial begin
    clk                   = 1'b0;
    rst_n                 = 1'b0;
    checkpoint_done       = 1'b0;
    mem_write_valid       = 1'b0;
    mem_write_addr        = '0;
    predicted_idle_cycles = '0;

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    write_address(32'h0000_0000);
    expect_count(1);

    // 同一32字节区域内重复写入，计数不应增加。
    write_address(32'h0000_0004);
    expect_count(1);

    write_address(32'h0000_0020);
    expect_count(2);

    if (checkpoint_cycles !== 32'd32) begin
      $fatal(1, "checkpoint_cycles=%0d, expected=32", checkpoint_cycles);
    end
    if (deep_threshold !== 32'd72) begin
      $fatal(1, "deep_threshold=%0d, expected=72", deep_threshold);
    end

    predicted_idle_cycles = 32'd4;
    #1;
    if (sleep_mode !== MODE_KEEP) $fatal(1, "expected MODE_KEEP");

    predicted_idle_cycles = 32'd20;
    #1;
    if (sleep_mode !== MODE_LIGHT) $fatal(1, "expected MODE_LIGHT");

    predicted_idle_cycles = 32'd200;
    #1;
    if (sleep_mode !== MODE_DEEP_OFF) $fatal(1, "expected MODE_DEEP_OFF");

    @(negedge clk);
    checkpoint_done = 1'b1;
    @(negedge clk);
    checkpoint_done = 1'b0;
    expect_count(0);

    $display("[PASS] SRTP controller framework smoke test passed.");
    $finish;
  end

endmodule

