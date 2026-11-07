`timescale 1ns/1ps

module sleep_mode_selector #(
  parameter int unsigned TIME_WIDTH             = 32,
  parameter int unsigned LIGHT_ENTRY_CYCLES     = 4,
  parameter int unsigned LIGHT_WAKE_CYCLES      = 4,
  parameter int unsigned DEEP_ENTRY_CYCLES      = 8,
  parameter int unsigned DEEP_WAKE_CYCLES       = 32
) (
  input  logic [TIME_WIDTH-1:0] predicted_idle_cycles_i,
  input  logic [TIME_WIDTH-1:0] checkpoint_cycles_i,
  output logic [TIME_WIDTH-1:0] light_threshold_o,
  output logic [TIME_WIDTH-1:0] deep_threshold_o,
  output srtp_types_pkg::sleep_mode_e sleep_mode_o
);

  import srtp_types_pkg::*;

  always_comb begin
    light_threshold_o = LIGHT_ENTRY_CYCLES + LIGHT_WAKE_CYCLES;
    deep_threshold_o  = checkpoint_cycles_i
                      + DEEP_ENTRY_CYCLES
                      + DEEP_WAKE_CYCLES;

    if (predicted_idle_cycles_i <= light_threshold_o) begin
      sleep_mode_o = MODE_KEEP;
    end else if (predicted_idle_cycles_i <= deep_threshold_o) begin
      sleep_mode_o = MODE_LIGHT;
    end else begin
      sleep_mode_o = MODE_DEEP_OFF;
    end
  end

endmodule

