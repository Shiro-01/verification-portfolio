# AXI-Stream FIFO UVM Verification Environment

## 📌 Project Overview
This repository contains a **UVM (Universal Verification Methodology)** environment designed to verify a VHDL-based AXI-Stream FIFO. The project demonstrates constrained random stimulus, transaction-level modeling (TLM), and automated scoreboard checking.

The goal of this environment is to stress-test the **handshake logic** ($TVALID$ / $TREADY$) and ensure 100% data integrity under various backpressure scenarios.

---

## 🏗️ Architecture
The testbench follows a standard UVM hierarchical structure for maximum reusability:

### 1. Data Object (`axis_item`)
Defines the AXI-Stream packet. It includes:
* **rand bit [31:0] data**: The actual payload.
* **rand int delay**: A randomized constraint used to inject "bubbles" into the stream, testing the FIFO's ability to handle non-consecutive data.

### 2. Interface (`axis_if`)
The bridge between the SV Testbench and VHDL RTL. 
* Uses **Clocking Blocks** to eliminate race conditions.
* Defines setup/hold skews to mimic real hardware timing.

### 3. Driver & Monitor
* **Driver**: Actively drives the $TVALID$ and $TDATA$ signals. It implements a blocking wait for $TREADY$, ensuring it adheres strictly to the AXI-Stream protocol.
* **Monitor**: A passive observer that captures successful transfers (where $TVALID$ and $TREADY$ are both high) and broadcasts them via a **UVM Analysis Port**.

### 4. Scoreboard
* Uses a **SystemVerilog Queue** to store expected data.
* Performs real-time comparison. If the FIFO drops a packet or reorders data, the scoreboard triggers a `UVM_ERROR`.
