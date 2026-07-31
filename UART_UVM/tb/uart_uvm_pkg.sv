// ---------------------------------------------------------------------------
// uart_uvm_pkg.sv
//
// UVM environment for axistream_uart.vhd. Two independent verification
// paths, run concurrently, because the DUT is full-duplex and the two
// paths exercise opposite roles:
//
//   RX path : the environment plays the external transmitter. It bit-bangs
//             uart_rxd (legal frames + deliberate framing/parity errors)
//             and checks dout / dout_valid / frame_error / parity_error.
//
//   TX path : the environment plays the AXI-Stream host. It pushes bytes
//             into din/din_valid and checks the resulting serial waveform
//             on uart_txd by decoding it exactly as a real receiving UART
//             would (mid-bit sampling, no access to DUT internals).
//
// IMPORTANT: BAUDRATE, PARITY_BIT, EIGHT_BIT, TWO_STOP_BITS and OVERSAMPLE
// are VHDL *generics* -- fixed at elaboration, not randomizable at run
// time. The localparams below MUST match whatever generic values tb_top.sv
// gives the DUT instance. To cover other parity/width/stop-bit
// configurations, re-elaborate with different generics and re-run; see the
// build PDF for why this is a real constraint and not a shortcut.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
`timescale 1ns/1ps

package uart_uvm_pkg;
  import uvm_pkg::*;

  // ---- must mirror the DUT generics used in tb_top.sv ---------------------
  localparam int    BAUDRATE      = 115_200;
  localparam int    CLK_FREQ_HZ   = 100_000_000;
  localparam byte   PARITY_MODE   = "E";     // 'N', 'E', or 'O' -- matches PARITY_BIT
  localparam bit    EIGHT_BIT     = 1'b1;    // matches EIGHT_BIT generic
  localparam bit    TWO_STOP_BITS = 1'b0;    // matches TWO_STOP_BITS generic

  localparam int    PAYLOAD_BITS  = EIGHT_BIT ? 8 : 7;
  localparam int    STOP_BITS     = TWO_STOP_BITS ? 2 : 1;
  localparam int    PARITY_BITS   = (PARITY_MODE == "N") ? 0 : 1;
  localparam real   BIT_PERIOD_NS = 1_000_000_000.0 / BAUDRATE;

  localparam int    BIT_PERIOD_NS_I = (BAUDRATE > 0) ? (1_000_000_000 + BAUDRATE/2) / BAUDRATE : 1;

  function automatic bit calc_parity(bit [7:0] d);
    return ^d[PAYLOAD_BITS-1:0];
  endfunction

  function automatic bit expected_parity_bit(bit [7:0] d);
    bit p = calc_parity(d);
    return (PARITY_MODE == "O") ? ~p : p;
  endfunction

  // =========================================================================
  // RX path: sequence item the driver bit-bangs onto uart_rxd
  // =========================================================================
  class uart_rx_item extends uvm_sequence_item;
    rand bit [7:0]   data;
    rand bit          inject_framing_error;
    rand bit          inject_parity_error;
    rand int unsigned gap_ns;   // idle time on the line before this frame

    constraint c_gap {
      gap_ns dist { [BIT_PERIOD_NS_I:BIT_PERIOD_NS_I*3] :/ 90, 0 :/ 10 };
    }
    constraint c_frame_err {
      inject_framing_error dist { 0 :/ 90, 1 :/ 10 };
    }
    constraint c_parity_err {
      if (PARITY_BITS == 0) inject_parity_error == 0;
      else inject_parity_error dist { 0 :/ 90, 1 :/ 10 };
    }

    `uvm_object_utils_begin(uart_rx_item)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(inject_framing_error, UVM_ALL_ON)
      `uvm_field_int(inject_parity_error, UVM_ALL_ON)
      `uvm_field_int(gap_ns, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "uart_rx_item");
      super.new(name);
    endfunction
  endclass

  // observed on the DUT's AXI-Stream read side, for the RX path scoreboard
  class axis_obs_item extends uvm_sequence_item;
    bit [7:0] data;
    bit       frame_err;
    bit       parity_err;

    `uvm_object_utils_begin(axis_obs_item)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(frame_err, UVM_ALL_ON)
      `uvm_field_int(parity_err, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axis_obs_item");
      super.new(name);
    endfunction
  endclass

  class uart_rx_random_seq extends uvm_sequence #(uart_rx_item);
    `uvm_object_utils(uart_rx_random_seq)
    rand int unsigned num_items = 150;

    function new(string name = "uart_rx_random_seq");
      super.new(name);
    endfunction

    task body();
      uart_rx_item item;
      repeat (num_items) begin
        item = uart_rx_item::type_id::create("item");
        start_item(item);
        if (!item.randomize())
          `uvm_error("SEQ", "randomize() failed in uart_rx_random_seq")
        finish_item(item);
      end
    endtask
  endclass

  // biases toward the corner cases plain randomization visits too rarely
  class uart_rx_error_seq extends uart_rx_random_seq;
    `uvm_object_utils(uart_rx_error_seq)

    function new(string name = "uart_rx_error_seq");
      super.new(name);
    endfunction

    task body();
      uart_rx_item item;
      repeat (num_items) begin
        item = uart_rx_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
              inject_framing_error dist { 0 :/ 40, 1 :/ 60 };
              if (PARITY_BITS == 1) inject_parity_error dist { 0 :/ 40, 1 :/ 60 };
            })
          `uvm_error("SEQ", "randomize() failed in uart_rx_error_seq")
        finish_item(item);
      end
    endtask
  endclass

  typedef uvm_sequencer #(uart_rx_item) uart_rx_sequencer;

  // driver: plays the external UART transmitter, bit-bangs uart_rxd
  class uart_rx_driver extends uvm_driver #(uart_rx_item);
    `uvm_component_utils(uart_rx_driver)

    virtual axis_uart_if vif;
    uvm_analysis_port #(uart_rx_item) ap; // broadcasts "intended" items

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axis_uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for uart_rx_driver")
      ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
      uart_rx_item item;
      vif.uart_rxd = 1'b1;
      wait (vif.rst_n === 1'b1);
      forever begin
        seq_item_port.get_next_item(item);
        drive_item(item);
        ap.write(item);
        seq_item_port.item_done();
      end
    endtask

    task drive_item(uart_rx_item item);
      int i;
      bit parity_bit;

      #(item.gap_ns * 1ns);

      // start bit
      vif.uart_rxd = 1'b0;
      #(BIT_PERIOD_NS * 1ns);

      // data bits, LSB first
      for (i = 0; i < PAYLOAD_BITS; i++) begin
        vif.uart_rxd = item.data[i];
        #(BIT_PERIOD_NS * 1ns);
      end

      // parity bit, if this build has one
      if (PARITY_BITS == 1) begin
        parity_bit = expected_parity_bit(item.data);
        if (item.inject_parity_error) parity_bit = ~parity_bit;
        vif.uart_rxd = parity_bit;
        #(BIT_PERIOD_NS * 1ns);
      end

      // stop bit(s) -- corrupt the first one to inject a framing error
      for (i = 0; i < STOP_BITS; i++) begin
        vif.uart_rxd = (item.inject_framing_error && i == 0) ? 1'b0 : 1'b1;
        #(BIT_PERIOD_NS * 1ns);
      end

      vif.uart_rxd = 1'b1; // back to idle
    endtask
  endclass

  // monitor: AXI-Stream read side of the DUT (dout/dout_valid/dout_ready)
  class axis_rx_monitor extends uvm_component;
    `uvm_component_utils(axis_rx_monitor)

    virtual axis_uart_if vif;
    uvm_analysis_port #(axis_obs_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axis_uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for axis_rx_monitor")
      ap = new("ap", this);
    endfunction

    // occasionally throttles dout_ready to exercise the DUT's "hold until
    // accepted" AXI-Stream backpressure behaviour
    task drive_backpressure();
      forever begin
        vif.dout_ready <= 1'b1;
        @(posedge vif.clk);
        if ($urandom_range(0, 9) == 0) begin
          vif.dout_ready <= 1'b0;
          repeat ($urandom_range(1, 3)) @(posedge vif.clk);
        end
      end
    endtask

    task run_phase(uvm_phase phase);
      axis_obs_item item;
      fork
        drive_backpressure();
      join_none
      forever begin
        @(posedge vif.clk);
        if (vif.dout_valid && vif.dout_ready) begin
          item            = axis_obs_item::type_id::create("item");
          item.data       = vif.dout;
          item.frame_err  = vif.frame_error;
          item.parity_err = vif.parity_error;
          ap.write(item);
        end
      end
    endtask
  endclass

  class uart_rx_scoreboard extends uvm_component;
    `uvm_component_utils(uart_rx_scoreboard)

    uvm_tlm_analysis_fifo #(uart_rx_item)  exp_fifo;
    uvm_tlm_analysis_fifo #(axis_obs_item) obs_fifo;
    int num_checked, num_pass, num_fail;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      exp_fifo = new("exp_fifo", this);
      obs_fifo = new("obs_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
      uart_rx_item  e;
      axis_obs_item o;
      forever begin
        exp_fifo.get(e);
        obs_fifo.get(o);
        compare_items(e, o);
      end
    endtask

    function void compare_items(uart_rx_item e, axis_obs_item o);
      bit exp_parity_err = (PARITY_BITS == 1) && e.inject_parity_error;
      bit exp_frame_err  = e.inject_framing_error;
      bit pass = (o.frame_err == exp_frame_err) && (o.parity_err == exp_parity_err)
                 && (exp_frame_err || (o.data == e.data[PAYLOAD_BITS-1:0]));
      num_checked++;
      if (pass) begin
        num_pass++;
        `uvm_info("RX_SB", $sformatf(
          "PASS data=0x%0h frame_err(exp/act)=%0b/%0b parity_err(exp/act)=%0b/%0b",
          e.data, exp_frame_err, o.frame_err, exp_parity_err, o.parity_err), UVM_HIGH)
      end else begin
        num_fail++;
        `uvm_error("RX_SB", $sformatf(
          "FAIL data(exp/act)=0x%0h/0x%0h frame_err(exp/act)=%0b/%0b parity_err(exp/act)=%0b/%0b",
          e.data, o.data, exp_frame_err, o.frame_err, exp_parity_err, o.parity_err))
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("RX_SB", $sformatf("RX path summary: checked=%0d pass=%0d fail=%0d",
                 num_checked, num_pass, num_fail), UVM_LOW)
    endfunction
  endclass

  class uart_rx_coverage extends uvm_component;
    `uvm_component_utils(uart_rx_coverage)
    uvm_analysis_imp #(uart_rx_item, uart_rx_coverage) ap;
    uart_rx_item item;

    covergroup cg;
      option.per_instance = 1;
      cp_frame_err:  coverpoint item.inject_framing_error;
      cp_parity_err: coverpoint item.inject_parity_error;
      cp_back2back:  coverpoint (item.gap_ns == 0) {
                       bins back_to_back = {1};
                       bins normal_gap   = {0};
                     }
      cx_frame_x_gap: cross cp_frame_err, cp_back2back;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
      ap = new("ap", this);
    endfunction

    function void write(uart_rx_item t);
      item = t;
      cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("RX_COV", $sformatf("RX-path functional coverage = %0.2f%%", cg.get_coverage()), UVM_LOW)
    endfunction
  endclass

  class uart_rx_agent extends uvm_agent;
    `uvm_component_utils(uart_rx_agent)
    uart_rx_sequencer sequencer;
    uart_rx_driver     driver;
    axis_rx_monitor    monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = axis_rx_monitor::type_id::create("monitor", this);
      if (get_is_active() == UVM_ACTIVE) begin
        sequencer = uart_rx_sequencer::type_id::create("sequencer", this);
        driver    = uart_rx_driver::type_id::create("driver", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  // =========================================================================
  // TX path: sequence item drives din/din_valid (host role)
  // =========================================================================
  class uart_tx_item extends uvm_sequence_item;
    rand bit [7:0] data;

    `uvm_object_utils_begin(uart_tx_item)
      `uvm_field_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "uart_tx_item");
      super.new(name);
    endfunction
  endclass

  // observed on uart_txd by decoding the serial waveform like a real
  // receiving UART would -- the monitor never looks inside the DUT
  class serial_obs_item extends uvm_sequence_item;
    bit [7:0] data;
    bit       frame_err;
    bit       parity_err;

    `uvm_object_utils_begin(serial_obs_item)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(frame_err, UVM_ALL_ON)
      `uvm_field_int(parity_err, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "serial_obs_item");
      super.new(name);
    endfunction
  endclass

  class uart_tx_random_seq extends uvm_sequence #(uart_tx_item);
    `uvm_object_utils(uart_tx_random_seq)
    rand int unsigned num_items = 100;

    function new(string name = "uart_tx_random_seq");
      super.new(name);
    endfunction

    task body();
      uart_tx_item item;
      repeat (num_items) begin
        item = uart_tx_item::type_id::create("item");
        start_item(item);
        if (!item.randomize())
          `uvm_error("SEQ", "randomize() failed in uart_tx_random_seq")
        finish_item(item);
      end
    endtask
  endclass

  typedef uvm_sequencer #(uart_tx_item) uart_tx_sequencer;

  // driver: plays the AXI-Stream host feeding the DUT's TX path
  class uart_tx_driver extends uvm_driver #(uart_tx_item);
    `uvm_component_utils(uart_tx_driver)

    virtual axis_uart_if vif;
    uvm_analysis_port #(uart_tx_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axis_uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for uart_tx_driver")
      ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
      uart_tx_item item;
      vif.din_valid = 1'b0;
      wait (vif.rst_n === 1'b1);
      forever begin
        seq_item_port.get_next_item(item);
        @(posedge vif.clk);
        wait (vif.din_ready === 1'b1);
        vif.din       <= item.data;
        vif.din_valid <= 1'b1;
        @(posedge vif.clk);
        vif.din_valid <= 1'b0;
        ap.write(item);
        seq_item_port.item_done();
      end
    endtask
  endclass

  // monitor: decodes uart_txd purely from the serial waveform, in real time
  class uart_tx_serial_monitor extends uvm_component;
    `uvm_component_utils(uart_tx_serial_monitor)

    virtual axis_uart_if vif;
    uvm_analysis_port #(serial_obs_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axis_uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for uart_tx_serial_monitor")
      ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
      serial_obs_item item;
      bit [7:0] data;
      bit       parity_bit_rx;
      bit       frame_err;
      int i;

      forever begin
        @(negedge vif.uart_txd);          // start bit begins
        #(1.5 * BIT_PERIOD_NS * 1ns);      // land on the centre of data bit 0

        data = 8'h00;
        for (i = 0; i < PAYLOAD_BITS; i++) begin
          data[i] = vif.uart_txd;
          #(BIT_PERIOD_NS * 1ns);
        end

        if (PARITY_BITS == 1) begin
          parity_bit_rx = vif.uart_txd;
          #(BIT_PERIOD_NS * 1ns);
        end

        frame_err = (vif.uart_txd !== 1'b1); // centre of the first stop bit

        item            = serial_obs_item::type_id::create("item");
        item.data       = data;
        item.frame_err  = frame_err;
        item.parity_err = (PARITY_BITS == 1) ? (parity_bit_rx != expected_parity_bit(data)) : 1'b0;
        ap.write(item);
      end
    endtask
  endclass

  class uart_tx_scoreboard extends uvm_component;
    `uvm_component_utils(uart_tx_scoreboard)

    uvm_tlm_analysis_fifo #(uart_tx_item)    exp_fifo;
    uvm_tlm_analysis_fifo #(serial_obs_item) obs_fifo;
    int num_checked, num_pass, num_fail;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      exp_fifo = new("exp_fifo", this);
      obs_fifo = new("obs_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
      uart_tx_item    e;
      serial_obs_item o;
      forever begin
        exp_fifo.get(e);
        obs_fifo.get(o);
        compare_items(e, o);
      end
    endtask

    function void compare_items(uart_tx_item e, serial_obs_item o);
      bit pass = (o.data == e.data[PAYLOAD_BITS-1:0]) && !o.frame_err && !o.parity_err;
      num_checked++;
      if (pass) begin
        num_pass++;
        `uvm_info("TX_SB", $sformatf("PASS data=0x%0h", e.data), UVM_HIGH)
      end else begin
        num_fail++;
        `uvm_error("TX_SB", $sformatf(
          "FAIL data(exp/act)=0x%0h/0x%0h frame_err=%0b parity_err=%0b",
          e.data, o.data, o.frame_err, o.parity_err))
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("TX_SB", $sformatf("TX path summary: checked=%0d pass=%0d fail=%0d",
                 num_checked, num_pass, num_fail), UVM_LOW)
    endfunction
  endclass

  class uart_tx_coverage extends uvm_component;
    `uvm_component_utils(uart_tx_coverage)
    uvm_analysis_imp #(uart_tx_item, uart_tx_coverage) ap;
    uart_tx_item item;

    covergroup cg;
      option.per_instance = 1;
      cp_data: coverpoint item.data {
        bins zero    = {8'h00};
        bins max     = {8'hFF};
        bins others  = default;
      }
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
      ap = new("ap", this);
    endfunction

    function void write(uart_tx_item t);
      item = t;
      cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("TX_COV", $sformatf("TX-path functional coverage = %0.2f%%", cg.get_coverage()), UVM_LOW)
    endfunction
  endclass

  class uart_tx_agent extends uvm_agent;
    `uvm_component_utils(uart_tx_agent)
    uart_tx_sequencer     sequencer;
    uart_tx_driver        driver;
    uart_tx_serial_monitor monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = uart_tx_serial_monitor::type_id::create("monitor", this);
      if (get_is_active() == UVM_ACTIVE) begin
        sequencer = uart_tx_sequencer::type_id::create("sequencer", this);
        driver    = uart_tx_driver::type_id::create("driver", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  // =========================================================================
  // Env / test: both paths run concurrently, matching real full-duplex use
  // =========================================================================
  class uart_env extends uvm_env;
    `uvm_component_utils(uart_env)

    uart_rx_agent      rx_agent;
    uart_rx_scoreboard rx_scoreboard;
    uart_rx_coverage   rx_coverage;

    uart_tx_agent      tx_agent;
    uart_tx_scoreboard tx_scoreboard;
    uart_tx_coverage   tx_coverage;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      rx_agent      = uart_rx_agent::type_id::create("rx_agent", this);
      rx_scoreboard = uart_rx_scoreboard::type_id::create("rx_scoreboard", this);
      rx_coverage   = uart_rx_coverage::type_id::create("rx_coverage", this);

      tx_agent      = uart_tx_agent::type_id::create("tx_agent", this);
      tx_scoreboard = uart_tx_scoreboard::type_id::create("tx_scoreboard", this);
      tx_coverage   = uart_tx_coverage::type_id::create("tx_coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      rx_agent.driver.ap.connect(rx_scoreboard.exp_fifo.analysis_export);
      rx_agent.monitor.ap.connect(rx_scoreboard.obs_fifo.analysis_export);
      rx_agent.driver.ap.connect(rx_coverage.ap);

      tx_agent.driver.ap.connect(tx_scoreboard.exp_fifo.analysis_export);
      tx_agent.monitor.ap.connect(tx_scoreboard.obs_fifo.analysis_export);
      tx_agent.driver.ap.connect(tx_coverage.ap);
    endfunction
  endclass

  class uart_base_test extends uvm_test;
    `uvm_component_utils(uart_base_test)
    uart_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = uart_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      uart_rx_random_seq rx_rand_seq;
      uart_rx_error_seq  rx_err_seq;
      uart_tx_random_seq tx_seq;

      phase.raise_objection(this);

      // both paths run concurrently -- exercises the DUT full-duplex
      fork
        begin
          rx_rand_seq = uart_rx_random_seq::type_id::create("rx_rand_seq");
          rx_rand_seq.num_items = 150;
          rx_rand_seq.start(env.rx_agent.sequencer);

          rx_err_seq = uart_rx_error_seq::type_id::create("rx_err_seq");
          rx_err_seq.num_items = 80;
          rx_err_seq.start(env.rx_agent.sequencer);
        end
        begin
          tx_seq = uart_tx_random_seq::type_id::create("tx_seq");
          tx_seq.num_items = 150;
          tx_seq.start(env.tx_agent.sequencer);
        end
      join

      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server svr = uvm_report_server::get_server();
      if (svr.get_severity_count(UVM_ERROR) == 0)
        `uvm_info("TEST", "** UVM TEST PASSED **", UVM_NONE)
      else
        `uvm_info("TEST", "** UVM TEST FAILED **", UVM_NONE)
    endfunction
  endclass

endpackage
