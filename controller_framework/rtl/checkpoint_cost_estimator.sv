`timescale 1ns/1ps

module checkpoint_cost_estimator #(
  parameter int unsigned NUM_REGIONS             = 128,
  parameter int unsigned FIXED_OVERHEAD_CYCLES   = 16,
  parameter int unsigned CYCLES_PER_REGION       = 8,
  parameter int unsigned COST_WIDTH              = 32,
  localparam int unsigned COUNT_W                = $clog2(NUM_REGIONS + 1)
) (
  input  logic [COUNT_W-1:0]    modified_count_i,
  output logic [COST_WIDTH-1:0] checkpoint_cycles_o
);

  always_comb begin
    checkpoint_cycles_o = FIXED_OVERHEAD_CYCLES
                        + modified_count_i * CYCLES_PER_REGION;
  end

endmodule

