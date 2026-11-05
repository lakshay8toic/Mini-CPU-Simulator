# Demonstration guide (about 5 minutes)

## Before the demo
- Open `src/MINICPU.ASM` in emu8086, click **Compile**, then **Run**.
- Set the emulator speed slider to the **fastest** setting.
- Click inside the emulator screen window so it receives your key presses.

## 1. Menu and instruction set (30 s)
Press `5`. Explain the following:
- Instructions are 2 bytes long.
- There are 4 registers, and R0 is always 0.
- There are 11 instructions, covering 4 addressing modes: register, immediate, absolute and index.

Press any key to return to the menu.

## 2. Demo 1, stage by stage (2 min)
Press `1`. The listing shows the machine code next to the assembly. Press any key to start the simulator, then press `Enter` five times for `LOAD R1, 30h(R0)`:

| Key | What to point at |
|---|---|
| Enter | **FETCH**: IR = `6430`, PC jumps 00 to 02, and `>` marks the instruction in memory |
| Enter | **DECODE**: RA and RB are read from the register file |
| Enter | **ALU**: RZ = 30, the *effective address* (X + [R0]) |
| Enter | **MEMORY**: MA = 30, MD = 07 (the value read from memory), RY = 07 |
| Enter | **WRITE-BACK**: R1 = 07, and the instruction counter becomes 1 |

Press `I` three times to run whole instructions: the second LOAD, the ADD (R3 = 0C), and the STORE.
After the STORE, `*0C` appears at address 32h. Press `I` again for OUT, then once more for HALT.

## 3. Demo 2, branching (1 min)
Press `2`, then any key, then `R`. The output shows `05 04 03 02 01 00`.
Explain how `BEQ` is decided in the ALU stage, and how `55 FF` encodes `#-1` in two's complement.

## 4. Demo 3, index addressing (1 min)
Press `3`, then any key, then `R`. The output is `12` hex = 18, and `*12` appears at address 3Fh.
`LOAD R3, 2Fh(R2)` uses index mode: the effective address is 2Fh + i.

## 5. Your own program (optional)
Press `4` and type `5403` `5804` `1D02` `A300` `.`
This program computes 3 + 4 = 7 and outputs `07`.

## Questions you may be asked
- **Why five stages for every instruction?** Using the same hardware stages for every instruction keeps the control simple. Unused stages do no work. This is also what allows pipelining (Unit III).
- **What are RA, RB, RZ, RM and RY?** They are inter-stage registers. Each one holds the result of one stage for the next stage, like the buffers between pipeline stages.
- **Hardwired or microprogrammed?** Hardwired. The control signals come directly from the opcode and the stage number, which is the step counter.
- **Why is R0 always 0?** It makes `X(R0)` act as absolute addressing, so the processor does not need a separate addressing mode for it.
- **CPI?** 5 for every instruction, and 2 for HALT.
- **How is the 8086 used?** The 8086 program keeps the simulated CPU's registers and memory in its own data segment. It decodes fields with `SHR` and `AND`, and does the arithmetic with its own ALU (`ADD`, `SUB`, `AND`, `OR`), copying the 8086 Z and C flags into the simulated flags. It draws the screen with INT 21h and INT 10h, and reads keys with INT 16h.
