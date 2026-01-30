# Digital Design & RTL Portfolio

This repository contains high-quality, verified hardware modules designed for FPGA and SoC integration. My work emphasizes "Verification-First" design, ensuring that every IP core is backed by a robust, self-checking environment.

## 🛠 Featured Project: SPI Master IP

**Core Logic:** A parameterized VHDL SPI Master supporting high-speed peripheral communication.

### Key Technical Features:
* **Protocol Support:** Mode 0 (CPOL=0, CPHA=0) with flexible clock frequency and data widths.
* **Control Flow:** Optimized `ena` and `last_byte` logic for seamless multi-byte frame handling.
* **Automated Verification:** * Includes a **Bus Functional Model (BFM)** acting as a behavioral SPI Slave.
    * **Self-Checking Architecture:** Real-time data integrity validation using VHDL `assert` statements.
    * **Edge Case Testing:** Validates `CS_n` de-assertion timing to ensure frame synchronization.

[View Project Directory](./spi_master)

---

## 🛰 Industrial Experience (Rocket Factory Augsburg)

During my tenure at RFA, I focused on high-speed data acquisition and SoC verification. While that specific codebase is proprietary, my experience includes:

* **ADC Controller Design:** Developing parallel interfaces for 16-channel SAR ADCs.
* **AXI-Stream Integration:** Designing Master interfaces with full backpressure (`TREADY`) and packetization (`TLAST`).
* **System-Level Verification:** Building complex behavioral models to simulate hardware delays and bus contention.

---

## 💻 Tech Stack
* **Languages:** VHDL, SystemVerilog
* **Tools:** Vivado, QuestaSim, GHDL/GTKWave
* **Specialties:** Synchronous Design, AXI-Stream, Protocol BFMs