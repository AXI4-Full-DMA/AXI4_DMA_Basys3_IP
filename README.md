# AXI4-Full DMA Controller for Basys3

![Verilog](https://img.shields.io/badge/Language-Verilog-blue) ![Python](https://img.shields.io/badge/Verification-Python-yellow) ![Vivado](https://img.shields.io/badge/Tool-Vivado%20202x.x-green) ![Board](https://img.shields.io/badge/Board-Basys3-orange)

## 📖 Project Overview
This project implements a high-performance **AXI4-Full Direct Memory Access (DMA) Controller** targeting the **Basys3 FPGA** board.

Since the Basys3 board lacks external DDR memory, we constructed a **"Virtual DDR System"** using on-chip **BRAM Controllers**. The designed IP complies with the standard AXI4-Full protocol (Burst Mode, Outstanding Transactions), making it fully portable to Zynq-based systems with DDR memory.

### 🎯 Key Objectives
* **High Performance:** Implementation of AXI4-Full Burst Mode (Max 16 beats).
* **Reliability:** Hardware constraints handling (4KB Boundary Check).
* **Verification:** Automated verification environment using **Python Golden Model**.
* **System Integration:** Fully integrated with MicroBlaze Soft-Core Processor.

---

## ⚙️ Technical Specifications

| Feature | Specification | Note |
| :--- | :--- | :--- |
| **Protocol** | AXI4-Full Master | MM2S (Read) & S2MM (Write) |
| **Data Width** | 32-bit | Compatible with MicroBlaze |
| **Address Width** | 32-bit | 4GB Address Space |
| **Burst Length** | Max 16 Beats | Optimized for BRAM Latency |
| **FIFO Depth** | 1024 Words | Async Clock Domain Crossing |
| **Clock Freq** | 100 MHz | System Clock |

---

## 🏗️ System Architecture

The DMA consists of a Control Slave (AXI4-Lite) for CPU configuration, two AXI4-Full Masters for data movement, and an asynchronous FIFO for data buffering.

![Block Diagram](./docs/images/dma_block_diagram.png)
*(Please upload your block diagram image to docs/images folder)*

### Memory Map
The system uses AXI BRAM Controllers to simulate source and destination memory spaces.

* **DMA Control Register:** `0x44A0_0000`
* **Source Memory (BRAM 0):** `0xC000_0000` (Read-Only)
* **Dest Memory (BRAM 1):** `0xC200_0000` (Write-Only)

---

## 👥 Team & Roles (R&R)

This project was executed by a team of 4, simulating a Fabless design team structure.

| Role | Responsibility | Main Tech Stack |
| :--- | :--- | :--- |
| **Team Leader (Team 4)** | **Project Lead & Control Logic** <br> - AXI4-Lite Slave & FIFO Integration <br> - SW Driver (C) & Architecture Design | Verilog, C, Git |
| **RTL Designer (Team 3)** | **Core IP Design (Datapath)** <br> - Read/Write Master FSM <br> - AXI4 Protocol Handling (Burst, 4KB) | Verilog, Waveform |
| **Verification (Team 1)** | **Simulation & Modeling** <br> - Python Golden Model & Data Generator <br> - Automated Verification Scripts | Python, Pandas |
| **System Eng (Team 2)** | **FPGA Implementation** <br> - Vivado Block Design & ILA Debugging <br> - Timing Analysis & Place/Route | Vivado, Tcl |

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
├── sw/                 # Embedded Software (Drivers)
└── vivado/             # Constraints (.xdc) & IP Repo
