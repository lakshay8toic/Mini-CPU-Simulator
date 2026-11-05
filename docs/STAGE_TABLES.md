# Five-stage execution tables

Every instruction uses the same five-stage hardware. Some stages do no useful work for some instructions; the simulator still spends one clock cycle in them and shows **No action**.

## Stage 1 : FETCH (same for every instruction)

| Action | Control signals |
|---|---|
| `MA <- [PC]`, `IR <- Mem[MA]`, `PC <- [PC] + 2` | `PCout, MAin, MEMread, MDout, IRin, INC2, PCin` |

## Stage 2 : DECODE (same for every instruction except HALT and JMP)

| Action | Control signals |
|---|---|
| `RA <- [Rsrc]`, `RB <- [Rsrc2]` | `RF_Aout, RF_Bout, RAin, RBin` |

Port B reads `Rt` for the register-form ALU instructions (ADD, SUB, AND, OR) and reads `Rd` for every other instruction.
`HALT` stops the clock at this stage. `JMP` does not read any registers.

## Stages 3 to 5 by instruction

| Instruction | 3 ALU | 4 MEMORY | 5 WRITE-BACK |
|---|---|---|---|
| `ADD Rd,Rs,Rt` | `RZ <- [RA] + [RB]` | `RY <- [RZ]` | `Rd <- [RY]` |
| `SUB Rd,Rs,Rt` | `RZ <- [RA] - [RB]` | `RY <- [RZ]` | `Rd <- [RY]` |
| `AND Rd,Rs,Rt` | `RZ <- [RA] AND [RB]` | `RY <- [RZ]` | `Rd <- [RY]` |
| `OR Rd,Rs,Rt` | `RZ <- [RA] OR [RB]` | `RY <- [RZ]` | `Rd <- [RY]` |
| `ADDI Rd,Rs,#imm` | `RZ <- [RA] + Imm` | `RY <- [RZ]` | `Rd <- [RY]` |
| `LOAD Rd,X(Rs)` | `RZ <- [RA] + X` (effective address) | `MA <- [RZ]`, `MD <- Mem[MA]`, `RY <- [MD]` | `Rd <- [RY]` |
| `STORE Rd,X(Rs)` | `RZ <- [RA] + X`, `RM <- [RB]` | `MA <- [RZ]`, `Mem[MA] <- [RM]` | No action |
| `BEQ Rd,Rs,X` | compare `[RB] - [RA]`; if Z = 1 then `PC <- X` | No action | No action |
| `JMP X` | `PC <- X` | No action | No action |
| `OUT Rs` | `RZ <- [RA]` (pass) | `OUTPUT <- [RZ]` | No action |

## Control signals in stages 3 to 5

| Instruction | Stage 3 | Stage 4 | Stage 5 |
|---|---|---|---|
| ADD/SUB/AND/OR | `RAout, MuxB=RB, ALU_op, RZin` | `RZout, MuxY=RZ, RYin` | `RYout, RF_Cin` |
| ADDI | `RAout, MuxB=Imm, ALU_add, RZin` | `RZout, MuxY=RZ, RYin` | `RYout, RF_Cin` |
| LOAD | `RAout, MuxB=Imm, ALU_add, RZin` | `MAin, MEMread, MuxY=MD, RYin` | `RYout, RF_Cin` |
| STORE | `RAout, MuxB=Imm, ALU_add, RZin, RMin` | `MAin, RMout, MEMwrite` | - |
| BEQ | `ALU_sub` (+ `Imm out, MuxPC, PCin` if taken) | - | - |
| JMP | `Imm out, MuxPC, PCin` | - | - |
| OUT | `RAout, ALU_pass, RZin` | `RZout, IOwrite` | - |

## Comparison with the course slides

| Slides (32-bit RISC) | This simulator (8-bit teaching CPU) |
|---|---|
| 32-bit instruction, `PC <- [PC] + 4` | 16-bit instruction, `PC <- [PC] + 2` |
| 32 registers, R0 = 0 | 4 registers, R0 = 0 |
| `Load R5, X(R7)` | `LOAD R3, 2Fh(R2)` (Demo 3) |
| `Add R3, R4, R5` | `ADD R3, R1, R2` (Demo 1) |
| `Store R6, X(R8)` | `STORE R1, 3Fh(R0)` (Demo 3) |
| Same five stages and inter-stage registers RA, RB, RZ, RM, RY | Same five stages and inter-stage registers RA, RB, RZ, RM, RY |

Clock cycles per instruction (CPI) = **5** for every instruction except `HALT`, which takes 2. For example, Demo 1 runs 5 instructions × 5 + HALT 2 = **27 clocks**, and the simulator's counter shows the same number.
