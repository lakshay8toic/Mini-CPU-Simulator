"""Automated tests for MINICPU.ASM   (run:  python3 test_minicpu.py)"""
import re
from dosemu import build, run, SRC


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def run_with(src_text, keys=" " * 200):
    """Run a modified copy of the source (used to test other programs)."""
    import dosemu
    path = "/tmp/minicpu_test.asm"
    open(path, "w").write(src_text)
    old = dosemu.SRC
    dosemu.SRC = path
    try:
        return run(keys)
    finally:
        dosemu.SRC = old


source = open(SRC).read()

# 1. assembles for a plain 8086 with no warnings
code, warn = build()
check("assembles for cpu 8086 without warnings (%d bytes)" % len(code), warn.strip() == "")

# 2. the demo program: 9 + 5 - 3 = 11 (0B) stored at address 0C
screens, exited = run(" " * 100)
final = screens[-1]
check("program exits normally", exited)
check("result 0B stored at 0C", "Result at address 0C = 0B" in final)
check("final memory dump correct",
      "Memory  : 1D 2E 3F 4C 56 2E 00 00 00 00 00 00 0B 09 05 03" in final)

# 3. one key = one step : fetch, decode, execute of the first instruction
s = screens
check("start screen shows the program in memory",
      "Memory  : 1D 2E 3F 4C 56 2E 00" in s[0] and "[FETCH]" not in s[0])
check("step 1 FETCH : PC=01 MAR=00 MDR=1D IR=1D",
      s[1].rstrip().endswith("PC=01  MAR=00  MDR=1D  IR=1D  ACC=00"))
check("step 2 DECODE : opcode 01 address 0D",
      s[2].rstrip().endswith("[DECODE]  opcode = 01, address = 0D"))
check("step 3 EXECUTE LOAD : ACC=09",
      "LOAD  : ACC <- M[address]" in s[3] and
      "PC=01  MAR=0D  MDR=09  IR=1D  ACC=09" in s[3])

# 4. ADD and SUB values
check("ADD gives ACC=0E (14)", "MDR=05  IR=2E  ACC=0E" in final or any("IR=2E  ACC=0E" in x for x in s))
check("SUB gives ACC=0B (11)", any("IR=3F  ACC=0B" in x for x in s))

# 5. JMP skips address 05
check("JMP sets PC=06", any("JMP   : PC <- address" in x and "PC=06  MAR=04" in x for x in s))
check("address 05 is never fetched", not any("MAR=05" in x for x in s))

# 7. changing the data in the source changes the result (live-demo idea)
changed = source.replace("00h, 09h, 05h, 03h", "00h, 14h, 06h, 02h")   # 20 + 6 - 2 = 24 = 18h
scr, _ = run_with(changed)
check("edited data 20+6-2 gives 18h", "Result at address 0C = 18" in scr[-1])

# 8. a program without JMP : LOAD, ADD, STORE, HALT
prog = "ram     db 1Dh, 2Eh, 4Ch, 00h, 00h, 00h, 00h, 00h"
changed = re.sub(r"ram     db [^\n]*", prog, source, count=1)
scr, _ = run_with(changed)
check("LOAD/ADD/STORE program gives 0E", "Result at address 0C = 0E" in scr[-1])

# 9. every line fits in the 80-column emu8086 screen
check("all lines shorter than 80 columns",
      all(len(l) < 80 for x in s for l in x.splitlines()))

print("\nALL TESTS PASSED")
