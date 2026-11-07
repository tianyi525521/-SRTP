`timescale 1ns/1ps

package srtp_types_pkg;
  typedef enum logic [1:0] {
    MODE_KEEP     = 2'b00,
    MODE_LIGHT    = 2'b01,
    MODE_DEEP_OFF = 2'b10
  } sleep_mode_e;
endpackage

