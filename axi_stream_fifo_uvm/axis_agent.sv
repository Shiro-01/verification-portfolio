class axis_agent extends uvm_agent;
  `uvm_component_utils(axis_agent)

  // Components of the Agent
  axis_driver    driver;
  axis_monitor   monitor;
  uvm_sequencer #(axis_item) sequencer;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Instantiate the components
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    monitor = axis_monitor::type_id::create("monitor", this);
    
    // Only create driver/sequencer if the agent is ACTIVE 
    if(get_is_active() == UVM_ACTIVE) begin
      driver    = axis_driver::type_id::create("driver", this);
      sequencer = uvm_sequencer#(axis_item)::type_id::create("sequencer", this);
    end
  endfunction

  // connecting the driver to the sequencer
  virtual function void connect_phase(uvm_phase phase);
    if(get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass