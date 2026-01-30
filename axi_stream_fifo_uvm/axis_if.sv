interface axis_if(input logic clk, input logic rst_n);
  // Signals 
  logic [31:0] tdata;
  logic        tvalid;
  logic        tready;

  // --- Clocking Block  ---
  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns; // Setup/Hold time simulations
    output tdata;
    output tvalid;
    input  tready;
  endclocking

  // Monitor Clocking Block 
  clocking mon_cb @(posedge clk);
    default input #1ns output #1ns;
    input tdata, tvalid, tready;
  endclocking

  // Modports
  modport driver (clocking drv_cb, input clk, rst_n);
  modport monitor (clocking mon_cb, input clk, rst_n);

endinterface