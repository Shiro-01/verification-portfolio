# SPI Master IP with Self-Checking Testbench

## Overview
A robust, parameterized SPI Master core implemented in VHDL. This IP provides a reliable communication bridge for peripheral sensors and was developed with a "Verification-First" mindset.

## Core Features
* **Protocol**: Supports SPI Mode 0 (CPOL=0, CPHA=0).
* **Interface**: Simple `ena` and `last_byte` control logic for easy integration.
* **Flexibility**: Parameterized clock frequency and data widths.

## Automated Verification
The quality of this IP is ensured by a self-checking VHDL testbench (`tb_spi_master.vhd`):
* **SPI Slave BFM**: A behavioral Bus Functional Model (BFM) acts as the SPI Slave, responding to the Master's clock and data lines.
* **Automated Data Integrity Checks**: Uses VHDL `assert` statements to compare transmitted data against "Golden Reference" values in real-time.
* **Frame Validation**: Specifically tests the `last_byte` logic to ensure the `CS_n` line de-asserts correctly only at the end of multi-byte frames.



## How to Run
1. Add `spi_master.vhd` and `tb_spi_master.vhd` to your simulation tool (Vivado/Questa/GHDL).
2. Run simulation for 1ms.
3. Check the simulator console for the message: `"TB: All SPI tests completed successfully."`
