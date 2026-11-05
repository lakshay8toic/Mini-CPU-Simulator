"""Automated tests for MINICPU.ASM  (run:  python3 tests/test_minicpu.py)"""
import re
from dosemu import run, build

def line(screen, prefix):
    for l in screen.splitlines():
        if l.strip().startswith(prefix):
            return l
    raise AssertionError("no line starting with %r" % prefix)

def final(keys):
    screens, exited = run(keys)
    return screens[-1], screens

def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name

# 0. it assembles for a plain 8086 with no warnings
code, warn = build()
check("assembles for cpu 8086 without warnings (%d bytes)" % len(code), warn.strip() == "")

# 1. Demo 1 run to HALT
s, _ = final("1 R")
check("demo1 HALT reached", "HALT : program finished" in s)
check("demo1 output 0C (=12)", "OUTPUT : 0C" in s and "last = 12" in s)
check("demo1 R1=07 R2=05 R3=0C", "R1=07  R2=05  R3=0C" in s)
check("demo1 Mem[32h]=0C stored", "07 05*0C" in line(s, "30h:"))
check("demo1 6 instructions, 27 clocks", "Instructions: 6   Clock: 27" in s)

# 2. Demo 1 stage by stage: verify the 5 stages of LOAD R1,30h(R0)
_, sc = final("1 " + "\r" * 5)
st = sc[3:8]
check("stage1 FETCH", "[1 FETCH]" in st[0] and "PC=02" in st[0] and "IR=6430" in st[0])
check("stage2 DECODE", "[2 DECODE]" in st[1] and "RF_Aout" in st[1])
check("stage3 ALU eff. address RZ=30", "[3 ALU]" in st[2] and "RZ=30" in st[2])
check("stage4 MEMORY reads 07", "[4 MEMORY]" in st[3] and "MA=30  MD=07" in st[3] and "RY=07" in st[3])
check("stage5 WRITE-BACK R1=07", "[5 WRITE-BACK]" in st[4] and "R1=07" in st[4] and "Instructions: 1" in st[4])

# 3. 'I' runs one whole instruction
_, sc = final("1 I")
check("I key completes one instruction", "Instructions: 1   Clock: 5" in sc[-1])

# 4. Demo 2 countdown
s, _ = final("2 R")
check("demo2 output 05 04 03 02 01 00", "OUTPUT : 05 04 03 02 01 00" in s)
check("demo2 HALT", "HALT : program finished" in s and "R1=00" in s)

# 5. Demo 3 array sum
s, _ = final("3 R")
check("demo3 sum = 12h (18)", "OUTPUT : 12" in s and "last = 18" in s)
check("demo3 Mem[3Fh]=12", "03 05 02 07 01" in line(s, "30h:") and line(s, "30h:").endswith("*12"))

# 6. Branch taken / not taken messages appear while stepping demo2
_, sc = final("2 " + "I" * 3 + "\r\r\r")
check("BEQ not-taken shown", any("not equal -> PC unchanged" in x for x in sc))

# 7. Custom program: type demo1 bytes manually, data at 30h
prog = "6430683" + "11D027C32A3000000"
keys = "4" + prog + "00" * (0x30 - len(prog) // 2) + "0705" + "." + " R"
s, sc = final(keys)
check("custom listing shown", any("Your own program" in x and "LOAD  R1, 30h(R0)" in x for x in sc))
check("custom program output 0C", "OUTPUT : 0C" in s)

# 8. Invalid hex key is rejected (beep) and lower-case accepted
s, sc = final("4" + "zg" + "a3" + "00" + "." + " R")
check("lowercase hex + invalid keys ignored -> OUT R3 runs", "OUT   R3" in sc[-2] or any("OUT   R3" in x for x in sc))

# 9. Illegal opcode
s, _ = final("4" + "F000" + "." + " R")
check("illegal opcode stops CPU", "Illegal opcode" in s)

# 10. Infinite loop hits the step limit
s, _ = final("4" + "9000" + "." + " R")
check("infinite loop -> step limit", "step limit reached" in s)

# 11. Write to R0 ignored
s, _ = final("4" + "5007" + "." + " R")   # ADDI R0,R0,#7
check("R0 stays 0", "R0=00" in s)

# 11b. program from docs/DEMO_GUIDE.md : 3 + 4 = 7
s, _ = final("4" + "540358041D02A300" + "." + " R")
check("demo-guide program outputs 07", "OUTPUT : 07" in s)

# 11c. demo-guide keystroke walkthrough of Demo 1 ends in HALT
s, _ = final("1 " + "\r" * 5 + "IIIII")
check("demo-guide walkthrough reaches HALT with *0C", "HALT : program finished" in s and "*0C" in s)

# 12. ISA screen and exit
screens, exited = run("5 6")
check("ISA screen shown", any("INSTRUCTION SET" in x for x in screens))
check("exit via 6 terminates", exited)

# 13. Q returns to menu
screens, _ = run("1 \rq")
check("Q returns to the menu", "Choose 1-6" in screens[-1])

# 14. every screen fits in 80x25
_, sc = final("3 " + "\r" * 40)
check("draw fits 80 columns", all(len(l) < 80 for x in sc for l in x.splitlines()))
print("\nALL TESTS PASSED")
