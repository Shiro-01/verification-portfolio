// ---------------------------------------------------------------------------
// tb_top.sv
// Instantiates the VHDL DUT (via axistream_uart_wrapper, generic-free from
// the SV side) and starts the UVM test. Requires a mixed-language (VHDL +
// SystemVerilog + UVM) simulator, e.g. Aldec Riviera-PRO or Questa.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_uvm_pkg::*;

module tb_top;

  logic clk = 0;
  always #5 clk = ~clk; // 100 MHz, matches CLK_FREQ_HZ in the wrapper

  axis_uart_if vif (.clk(clk));

  axistream_uart_wrapper dut (
    .clk          (clk),
    .rst_n        (vif.rst_n),
    .uart_txd     (vif.uart_txd),
    .uart_rxd     (vif.uart_rxd),
    .din          (vif.din),
    .din_valid    (vif.din_valid),
    .din_ready    (vif.din_ready),
    .dout         (vif.dout),
    .dout_valid   (vif.dout_valid),
    .dout_ready   (vif.dout_ready),
    .frame_error  (vif.frame_error),
    .parity_error (vif.parity_error)
  );

  initial begin
    vif.rst_n = 1'b0;
    repeat (5) @(posedge clk);
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db #(virtual axis_uart_if)::set(null, "*", "vif", vif);
    run_test();
  end

  // safety net: ~380 frames at 115200 baud is tens of ms of simulated time
  initial begin
    #200ms;
    `uvm_fatal("TIMEOUT", "simulation did not finish in time")
  end

endmodule
