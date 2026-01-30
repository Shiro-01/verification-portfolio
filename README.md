# RTL Design & Verification Portfolio

Welcome! 👋  
This repo is my personal portfolio of **FPGA/SoC-ready RTL modules**. My main focus is building designs that are **clean, reusable, and properly verified** 

My approach is simple:
- **Verification-first mindset** (self-checking testbenches whenever possible)
- **Readable RTL** (parameterized, documented, easy to integrate)
- **Real-world integration** (AXI streaming, backpressure, timing-friendly design)

---

## 🛠 Featured Project 1: SPI Master IP (VHDL)

A parameterized **VHDL SPI Master** for reliable high-speed peripheral communication.

**Highlights**
- **Protocol support:** Mode 1 (CPOL=0, CPHA=1) with configurable clock and data width.
- **Control flow:** Clean `ena` / `last_byte` handling for smooth multi-byte transfers.
- **Verification:** Includes a small but effective verification setup:
  - A **BFM** acting as a behavioral SPI Slave
  - **Self-checking** with VHDL `assert` statements
  - Edge-case coverage (e.g., `CS_n` de-assertion timing and frame sync)

➡️ **Project folder:** [SPI_MASTER](./SPI_MASTER)

---

## 🛠 Featured Project 2: AXI-Stream FIFO + UVM Verification (VHDL + SystemVerilog)

A **VHDL AXI-Stream FIFO** verified with a complete **UVM** environment (mixed-language).

**Highlights**
- **UVM structure:** Agent (Driver / Monitor / Sequencer) + Scoreboard for automated checks.
- **Protocol integrity:** Validates `TVALID` / `TREADY` behavior, backpressure handling, and corner cases via constrained-random stimulus.
- **Simulation:** Verified via **EDA Playground** using mixed-language (VHDL/SV).

➡️ **Project folder:** [axi_stream_fifo_uvm](./axi_stream_fifo_uvm)

---

## 🛰 Industrial Experience (Rocket Factory Augsburg)

During my internship at **Rocket Factory Augsburg (RFA)**, I worked on high-speed data acquisition and SoC verification topics.  
The project code itself is proprietary, so I can’t share it. but the experience strongly shaped how I design and verify RTL today.

**Relevant work I was involved in**
- **ADC controller design:** Parallel interfaces for multi-channel SAR ADCs.
- **AXI-Stream integration:** Master interfaces with full backpressure (`TREADY`) and packetization (`TLAST`).
- **System-level verification:** Behavioral models to emulate hardware delays, contention, and realistic timing.

---

## 💻 Some Tech Stack

- **Languages:** VHDL, SystemVerilog  
- **Tools:** Vivado, GHDL, GTKWave, EDA Playground
- **Focus areas:** Synchronous design, AXI-Stream, BFM, UVM

---

## Notes

If you’re reviewing this repo for a role and want more context (requirements, waveforms, verification strategy, etc.), feel free to ask. I’m happy to walk through the design decisions and trade-offs.
