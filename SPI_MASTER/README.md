# SPI Master IP (VHDL) — Self‑Checking Testbench Included

## Overview
This folder contains a **parameterized SPI Master** implemented in VHDL.  
The goal is a clean SPI core that’s easy to integrate in FPGA/SoC projects — and **verified properly**, not just “looks fine in waves”.

I built this with a *verification-first* mindset, so you’ll also find a self-checking testbench that validates real behavior and some important corner cases.

---

## Core Features
- **SPI Mode:** **Mode 1** (CPOL=0, CPHA=1) 
- **Integration-friendly control:** simple `ena` + `last_byte` control for clean multi-byte frames
- **Configurable:** parameterized clock frequency and data width

---

## Verification (Self‑Checking TB)
The IP is verified with a self-checking VHDL testbench: **`tb_spi_master.vhd`**.

What’s inside:
- **SPI Slave BFM:** a behavioral SPI Slave model that reacts to the Master’s `SCLK/MOSI/CS_n`
- **Mode‑1 timing behavior:** while `CS_n` is low, the BFM:
  - updates `MISO` on the **rising** edge of `SCLK`
  - samples `MOSI` on the **falling** edge of `SCLK`
- **Data integrity checks:** VHDL `assert` statements compare the received data against a golden reference automatically
- **Frame validation:** explicitly tests the `last_byte` behavior to ensure `CS_n` de-asserts only at the correct end-of-frame boundary

If the testbench completes without assertion failures, you get a solid baseline confidence in both the protocol behavior and the multi-byte framing logic.

---

## How to Run (quick)
1. Add these files to your simulator:
   - `spi_master.vhd`
   - `tb_spi_master.vhd`
2. Run the simulation for **~1 ms**
3. Check the console for:
   - **`TB: All SPI tests completed successfully.`**