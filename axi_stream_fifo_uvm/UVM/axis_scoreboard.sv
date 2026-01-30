`uvm_analysis_imp_decl(_input)
`uvm_analysis_imp_decl(_output)

class axis_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axis_scoreboard)

  // Input and output analysis streams
  uvm_analysis_imp_input  #(axis_item, axis_scoreboard) input_export;
  uvm_analysis_imp_output #(axis_item, axis_scoreboard) output_export;

  // Refrence Queue
  axis_item queue[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    input_export  = new("input_export", this);
    output_export = new("output_export", this);
  endfunction

  // Logic for data getting IN
  virtual function void write_input(axis_item item);
    axis_item copy;
    $cast(copy, item.clone());                                     //Sh: Create a copy so the monitor doesn't overwrite it
    queue.push_back(copy);
  endfunction

  // Logic for data getting OUT (The comparison)
  virtual function void write_output(axis_item item);
    if (queue.size() > 0) begin
      axis_item expected = queue.pop_front();
      
      if (item.data == expected.data) begin
        `uvm_info("SCB_MATCH", $sformatf("MATCH! Data: %h", item.data), UVM_LOW)
      end else begin
        `uvm_error("SCB_MISMATCH", $sformatf("ERROR! Expected: %h, Got: %h", expected.data, item.data))
      end
    end else begin
      `uvm_error("SCB_UNEXPECTED", "Output received but no input was recorded!")
    end
  endfunction

endclass