// ---------------------------------------------------------------------------
// axis_uart_if.sv
// Bundles every pin of axistream_uart for the UVM environment. One instance
// is bound to the VHDL DUT in tb_top.sv; the RX-path agent drives uart_rxd
// and the dout side, the TX-path agent drives din and observes uart_txd.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
interface axis_uart_if (input logic clk);
  logic rst_n;

  // serial pins
  logic uart_txd;   // DUT output, observed by the tx-path serial monitor
  logic uart_rxd;   // DUT input,  driven by the rx-path driver

  // AXI-Stream write side (host -> DUT -> uart_txd)
  logic [7:0] din;
  logic       din_valid;
  logic       din_ready;

  // AXI-Stream read side (uart_rxd -> DUT -> host)
  logic [7:0] dout;
  logic       dout_valid;
  logic       dout_ready;

  logic frame_error;
  logic parity_error;

  initial uart_rxd = 1'b1; // idle line high
endinterface
