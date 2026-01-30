class axis_driver extends uvm_driver #(axis_item);
  `uvm_component_utils(axis_driver)

  // the pointer to the "wires"
  virtual axis_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // build
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "Could not get virtual interface from config_db")
  endfunction

  // run
  virtual task run_phase(uvm_phase phase);
    // signals Initalisation
    vif.drv_cb.tvalid <= 0;
    vif.drv_cb.tdata  <= 0;

    // Wait for reset to be released
    wait(vif.rst_n == 1);
    
    forever begin
      // Requesting a new item from the Sequencer
      seq_item_port.get_next_item(req);
      
      // Driving the item to the pins
      drive_to_pins(req);
      
      // informing Sequencer we are done
      seq_item_port.item_done();
    end
  endtask

  // The AXI-Stream Handshake Logic task
  task drive_to_pins(axis_item item);
    // Applying random delays
    repeat(item.delay) @(vif.drv_cb);

    // Set Data and Valid
    vif.drv_cb.tdata  <= item.data;
    vif.drv_cb.tvalid <= 1;

    // WAIT for TREADY (The handshake)
    // We stay in this loop as long as the FIFO is FULL (tready = 0)
    do begin
      @(vif.drv_cb);
    end while (vif.drv_cb.tready !== 1);

    // Transfer complete! Drop valid
    vif.drv_cb.tvalid <= 0;
  endtask
endclass