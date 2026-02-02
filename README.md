# AXI4-Full DMA Controller for Basys3

![Verilog](https://img.shields.io/badge/Language-Verilog-blue) ![Python](https://img.shields.io/badge/Verification-Python-yellow) ![Vivado](https://img.shields.io/badge/Tool-Vivado%20202x.x-green) ![Board](https://img.shields.io/badge/Board-Basys3-orange)

## 📖 Project Overview
This project implements a high-performance **AXI4-Full Direct Memory Access (DMA) Controller** on the **Basys3 (Artix-7)** FPGA board.

Since the Basys3 board utilizes a pure FPGA fabric without a hardened PS (Processing System) or DDR memory, we architected a **MicroBlaze-based Soft SoC** system. We simulated the external memory environment using on-chip **BRAM Controllers** to verify the AXI4-Full Burst transactions.

Although demonstrated on Basys3, this IP is designed to be fully compliant with the standard **AXI4-Full protocol**, ensuring portability to **Zynq SoC** or generic DDR-based systems in the future.

### 🎯 Key Objectives
* **High Performance:** Implementation of AXI4-Full Burst Mode (Max 16 beats) for high throughput.
* **Reliability:** Handling hardware constraints such as 4KB Boundary Check.
* **Verification:** Automated verification environment using **Python Golden Model**.
* **System Integration:** SoC integration with **MicroBlaze Soft-Core Processor**.

---

## ⚙️ Technical Specifications

| Feature | Specification | Note |
| :--- | :--- | :--- |
| **Protocol** | AXI4-Full Master | MM2S (Read) & S2MM (Write) |
| **Processor**| **MicroBlaze** | Soft-Core CPU (32-bit) |
| **Data Width** | 32-bit | Optimized for MicroBlaze System |
| **Address Width** | 32-bit | 4GB Address Space Support |
| **Burst Length** | Max 16 Beats | Tuned for BRAM Latency |
| **FIFO Depth** | 1024 Words | Async Clock Domain Crossing |

---

## 🏗️ System Architecture

The system mimics a typical SoC structure using FPGA fabric logic. It includes a Control Slave for CPU configuration and two AXI4-Full Masters for data movement between memory spaces.

![Block Diagram](./docs/images/dma_block_diagram.png)

### Memory Map (Virtual DDR)
Since physical DDR is absent, we mapped AXI BRAM Controllers to specific address regions to act as Source/Destination memories.

* **DMA Control Register:** `0x44A0_0000`
* **Source Memory (BRAM 0):** `0xC000_0000` (Read-Only)
* **Dest Memory (BRAM 1):** `0xC200_0000` (Write-Only)

---

## 👥 Team & Roles (R&R)

This project was executed by a team of 4, simulating a professional Fabless IP design team.

| Role | Responsibility | Main Tech Stack |
| :--- | :--- | :--- |
| **Team Leader** | **Project Lead & Control Logic** <br> - AXI4-Lite Slave & FIFO Integration <br> - MicroBlaze Firmware (C) Development | Verilog, C, Git |
| **RTL Designer** | **Core IP Design (Datapath)** <br> - Read/Write Master FSM Design <br> - AXI4 Protocol Handling (Burst, Handshake) | Verilog, Waveform |
| **Verification** | **Simulation & Modeling** <br> - Python Golden Model & Data Generator <br> - Automated Verification Scripts | Python, Pandas |
| **System Eng** | **FPGA Implementation** <br> - Vivado Block Design (MicroBlaze System) <br> - ILA Debugging & Timing Closure | Vivado, Tcl |

---

## 📂 Repository Structure

```bash
AXI4_DMA_Basys3_IP/
├── docs/               # Specifications & Waveforms
├── rtl/                # Synthesizable Verilog Source Codes
│   ├── top_dma.v       # Top Module
│   ├── read_master.v   # AXI4-Full Read Master
│   ├── write_master.v  # AXI4-Full Write Master
│   └── ...
├── sim/                # Verification Environment
│   ├── python/         # Golden Model Generator
│   └── tb/             # Verilog Testbenches
├── sw/                 # Embedded Software (Vitis/SDK)
│   ├── dma_driver.c    # DMA Control Driver
│   └── main.c          # Test Application
└── vivado/             # Constraints (.xdc) & IP Repo
