`timescale 1ns/1ps

module modified_region_tracker #(
  parameter int unsigned ADDR_WIDTH   = 32,
  parameter int unsigned NUM_REGIONS  = 128,
  parameter int unsigned REGION_BYTES = 32,
  localparam int unsigned REGION_LSB  = $clog2(REGION_BYTES),
  localparam int unsigned REGION_W    = $clog2(NUM_REGIONS),
  localparam int unsigned COUNT_W     = $clog2(NUM_REGIONS + 1)
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  input  logic                   write_valid_i,
  input  logic [ADDR_WIDTH-1:0]  write_addr_i,
  output logic [NUM_REGIONS-1:0] modified_bitmap_o,
  output logic [COUNT_W-1:0]     modified_count_o
);

  logic [REGION_W-1:0] region_index;

  assign region_index = write_addr_i[REGION_LSB +: REGION_W];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      modified_bitmap_o <= '0;
      modified_count_o  <= '0;
    end else if (clear_i) begin
      modified_bitmap_o <= '0;
      modified_count_o  <= '0;
    end else if (write_valid_i && !modified_bitmap_o[region_index]) begin
      modified_bitmap_o[region_index] <= 1'b1;
      modified_count_o                <= modified_count_o + 1'b1;
    end
  end

endmodule

