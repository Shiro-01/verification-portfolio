import uvm_pkg::*;
`include "uvm_macros.svh"

class axis_item extends uvm_sequence_item;
  // random 32 bit vector
  rand bit [31:0] data;

  // A random delay between transfers to test the FIFO's empty/full states
  rand int delay;

  // a calmp for Keeping the randomization realistic
  constraint c_delay { delay inside {[0:10]}; }

  // automate copy, print, and compare functions
  `uvm_object_utils_begin(axis_item)
    `uvm_field_int(data,  UVM_ALL_ON)
    `uvm_field_int(delay, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axis_item");
    super.new(name);
  endfunction
endclass