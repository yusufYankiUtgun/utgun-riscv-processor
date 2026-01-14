# Custom RISC-V Processor & LLVM Compiler Extension

### Utgun ISA

<p align="center">
  <b>Custom 32-bit RISC-V architecture with LLVM backend support</b><br/>
  <i>Featuring hand-drawn datapath and control unit design</i>
</p>

---

## Project Overview

This project presents the **design and implementation of a custom 32-bit RISC-V processor** together with a corresponding **LLVM compiler backend extension**.

Key highlights:

- Multi-cycle RISC-V processor implemented in **Verilog**
- Custom **LLVM backend extension** enabled via `+utgun`
- Specialized instruction set (**Utgun ISA**) for arithmetic- and memory-intensive operations
- **Hand-drawn datapath and control unit diagrams** used as the primary architectural reference
- Complete flow: **C → LLVM IR → Object code → Verilog simulation**

---

## Hand-Drawn Architecture & Control Design

Before writing any Verilog, the processor architecture was **fully designed on paper**.

The document **`utgun_processor.pdf`** contains detailed, hand-drawn diagrams that include:

- Full **multi-cycle datapath** (Fetch, Decode, Execute, Writeback)
- **FSM-based control unit** with explicit state transitions
- Register file, ALU, immediate generator, and memory interfaces
- **Cycle-by-cycle execution behavior** for custom Utgun instructions

These drawings served as the **authoritative design specification** and directly guided:

- Control signal generation  
- FSM state definitions  
- Cycle counts for multi-cycle instructions  

This approach emphasizes **architectural reasoning and control design**, not just HDL implementation.

---

## Installation & Setup

> **Reproducibility notice:**  
> This project depends on a specific LLVM source version. Please follow the steps below carefully.

### Prerequisite: LLVM Source Setup

This project requires **LLVM 18.1.0**, tested with commit:

```
461274b81d8641eab64d494accddc81d7db8a09e
```

### 1. Clone LLVM

```bash
git clone https://github.com/llvm/llvm-project.git
cd llvm-project
git checkout 461274b81d8641eab64d494accddc81d7db8a09e
```

---

### 2. Integrate Custom Utgun Files

Copy and modify the following files inside the LLVM source tree:

- Copy custom instruction definitions:
  
  ```
  RISCVInstrInfoUtgun.td → llvm/lib/Target/RISCV/
  ```

- Modify `RISCVInstrInfo.td`: Add the include line **at the end of the file.**
  
  ```td
  include "RISCVInstrInfoUtgun.td"
  ```

- Update `RISCVFeatures.td` to define the **Utgun** extension:
  
  ```td
  def FeatureExtUtgun
      : SubtargetFeature<"utgun", "HasUtgun", "true",
                          "Enable Utgun ISA extensions">;
  ```

---

## Custom Instruction Set (Utgun ISA)

The Utgun ISA extends the base RISC-V instruction set with the following instructions:

| Instruction       | Assembly Format               | Description                                                                     |
| ----------------- | ----------------------------- | ------------------------------------------------------------------------------- |
| **SUB.ABS**       | `sub.abs rd, rs1, rs2`        | Computes `abs(rs1 - rs2)`                                                       |
| **AVG.FLR**       | `avg.flr rd, rs1, imm`        | Floor average of `rs1` and sign-extended immediate                              |
| **MOVU**          | `movu rd, rs1, imm`           | Writes unsigned-extended immediate to `rd`                                      |
| **SRT.CMP.ST**    | `srt.cmp.st rd, rs1, rs2`     | Sort & Store: smaller value → `[rd]`, larger → `[rd+4]`                         |
| **LD.CMP.MAX**    | `ld.cmp.max rd, rs1, rs2`     | Load Max: dereferences three pointers and keeps the maximum                     |
| **SRCH.BIT.PTRN** | `srch.bit.ptrn rd, rs1, rs2`  | Searches for an 8-bit pattern (from `rs2`) inside `rs1`                         |
| **SEL.PART**      | `sel.part rd, rs1, s1`        | Selects upper or lower 16 bits of `rs1`                                         |
| **SEL.CND**       | `sel.cnd rs1, rs2, imm, s2`   | Conditional branch using `AIM` bits: `00 (==)`, `01 (>=)`, `10 (<)`, `11 (NOP)` |
| **MAC.LD.ST**     | `mac.ld.st rs1, rs2, imm, s2` | Iterative **memory-to-memory** multiply-accumulate                              |

---

## Hardware Architecture

The processor uses a **multi-cycle architecture** with four stages:

### 1. Fetch

- Instruction fetch from memory
- **Endianness handling** (little-endian input → internal format)

### 2. Decode

- Instruction field decoding
- Register file read

### 3. Execute

- ALU and memory operations
- Variable execution latency for custom instructions:

| Instruction  | Execute Cycles |
| ------------ | -------------- |
| `SRT.CMP.ST` | 2              |
| `LD.CMP.MAX` | 3              |
| `MAC.LD.ST`  | `(s2 + 1) × 4` |

### 4. Writeback

- Writes final result to the register file

---

## How to Run

> **Note:** Commands assume execution from `llvm-project/build`.

### Step 1: Build LLVM with Utgun Support

```bash
cd llvm-project
mkdir build && cd build
cmake -G Ninja ../llvm   -DLLVM_TARGETS_TO_BUILD="RISCV"   -DCMAKE_BUILD_TYPE=Release
ninja -j$(nproc) clang llc llvm-objdump
```

---

### Step 2: Compile Code for Utgun ISA

```bash
# Generate LLVM IR
./bin/clang -S -emit-llvm   -target=riscv32-unknown-elf example.c -o example.ll

# Compile using Utgun extension
./bin/llc -mtriple=riscv32-unknown-elf -mattr=+utgun   -filetype=obj example.ll -o example.o

# Inspect generated machine code
./bin/llvm-objdump -d example.o
```

---

### Step 3: Verilog Simulation

Simulate the processor using **`utgun.v`**.

**Inputs**

- `clk_i` – clock
- `rst_i` – reset
- `inst_i` – 32-bit instruction

**Memory Model**

- Combinational read
- Sequential write

**Debug Signal**

- `cur_stage_o`
  - `0` → Fetch
  - `1` → Decode
  - `2` → Execute
  - `3` → Writeback

---

## Repository Structure

```text
.
├── README.md
├── hardware/
│   └── utgun.v
├── llvm/
│   ├── RISCVInstrInfoUtgun.td
│   ├── RISCVInstrInfo.td
│   └── RISCVFeatures.td
└── docs/
    └── utgun_processor.pdf
```
