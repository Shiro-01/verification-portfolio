# RTL Design & Verification Portfolio

Welcome! 👋  
This repo is my personal portfolio of **FPGA/SoC-ready RTL modules**. My main focus is building designs that are **clean, reusable, and properly verified** 

---

## 🛠 Featured Project 1: AXI-Stream FIFO + UVM Verification (VHDL + SystemVerilog)

A **VHDL AXI-Stream FIFO** verified with a complete **UVM** environment (mixed-language).

**Highlights**
- **UVM structure:** Agent (Driver / Monitor / Sequencer) + Scoreboard for automated checks.
- **Protocol integrity:** Validates `TVALID` / `TREADY` behavior, backpressure handling, and corner cases via constrained-random stimulus.
- **Simulation:** Verified via **EDA Playground** using mixed-language (VHDL/SV).

➡️ **Project folder:** [axi_stream_fifo_uvm](./axi_stream_fifo_uvm)

---

## 💻 Some Tech Stack

- **Languages:** VHDL, SystemVerilog  
- **Tools:** Vivado, GHDL, GTKWave, EDA Playground
- **Focus areas:** Synchronous design, AXI-Stream, BFM, UVM

---

## Notes

If you’re reviewing this repo for a role and want more context, feel free to ask. I’m happy to walk through the design decisions and trade-offs.
