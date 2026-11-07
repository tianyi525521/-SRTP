`timescale 1ns/1ps

module srtp_controller_top #(
  parameter int unsigned ADDR_WIDTH   = 32,
  parameter int unsigned NUM_REGIONS  = 128,
  parameter int unsigned REGION_BYTES = 32,
  parameter int unsigned TIME_WIDTH   = 32,
  localparam int unsigned COUNT_W     = $clog2(NUM_REGIONS + 1)
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  checkpoint_done_i,
  input  logic                  mem_write_valid_i,
  input  logic [ADDR_WIDTH-1:0] mem_write_addr_i,
  input  logic [TIME_WIDTH-1:0] predicted_idle_cycles_i,
  output logic [COUNT_W-1:0]    modified_count_o,
  output logic [TIME_WIDTH-1:0] checkpoint_cycles_o,
  output logic [TIME_WIDTH-1:0] deep_threshold_o,
  output srtp_types_pkg::sleep_mode_e sleep_mode_o
);

  modified_region_tracker #(
    .ADDR_WIDTH   (ADDR_WIDTH),
    .NUM_REGIONS  (NUM_REGIONS),
    .REGION_BYTES (REGION_BYTES)
  ) u_modified_region_tracker (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .clear_i           (checkpoint_done_i),
    .write_valid_i     (mem_write_valid_i),
    .write_addr_i      (mem_write_addr_i),
    .modified_bitmap_o (),
    .modified_count_o  (modified_count_o)
  );

  checkpoint_cost_estimator #(
    .NUM_REGIONS (NUM_REGIONS),
    .COST_WIDTH  (TIME_WIDTH)
  ) u_checkpoint_cost_estimator (
    .modified_count_i    (modified_count_o),
    .checkpoint_cycles_o (checkpoint_cycles_o)
  );

  sleep_mode_selector #(
    .TIME_WIDTH (TIME_WIDTH)
  ) u_sleep_mode_selector (
    .predicted_idle_cycles_i (predicted_idle_cycles_i),
    .checkpoint_cycles_i     (checkpoint_cycles_o),
    .light_threshold_o       (),
    .deep_threshold_o        (deep_threshold_o),
    .sleep_mode_o            (sleep_mode_o)
  );

endmodule

