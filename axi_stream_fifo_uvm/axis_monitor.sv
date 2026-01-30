class axis_monitor extends uvm_monitor;
  `uvm_component_utils(axis_monitor)

  virtual axis_if vif;

  uvm_analysis_port #(axis_item) item_collected_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON_NO_VIF", "Could not get vif for monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      axis_item observed_item = axis_item::type_id::create("observed_item");

      // Wait for a valid clock edge where a transfer happens
      // Sh: Note: - We use the monitor clocking block (mon_cb) for clean sampling
      do begin
        @(vif.mon_cb);
      end while (!(vif.mon_cb.tvalid === 1 && vif.mon_cb.tready === 1));

      // Sampling the data
      observed_item.data = vif.mon_cb.tdata;

      // Sending the item to the Analysis Port
      `uvm_info("MON", $sformatf("Observed transfer: Data = %h", observed_item.data), UVM_LOW)
      item_collected_port.write(observed_item);
    end
  endtask
endclass