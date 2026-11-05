"""
Tiny DOS .COM test harness for MINICPU.ASM.

1. Converts the emu8086 (MASM-style) source into NASM syntax and assembles it
   with `cpu 8086`, so any instruction that a real 8086 / emu8086 cannot run
   is rejected.
2. Runs the .COM file in the Unicorn CPU emulator with a fake 80x25 text
   screen, INT 21h (02h, 09h, 4Ch), INT 10h (00h) and INT 16h (00h) keyboard.

Usage:  from dosemu import build, run
"""
import os
import re
import subprocess
import tempfile

from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR
from unicorn.x86_const import (UC_X86_REG_AX, UC_X86_REG_DX, UC_X86_REG_DS,
                               UC_X86_REG_CS, UC_X86_REG_SS, UC_X86_REG_ES,
                               UC_X86_REG_SP, UC_X86_REG_IP)

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src", "MINICPU.ASM")


def to_nasm(text):
    out = ["cpu 8086"]
    for line in text.splitlines():
        line = re.sub(r"\bbyte ptr\b", "byte", line, flags=re.I)
        line = re.sub(r"\bword ptr\b", "word", line, flags=re.I)
        line = re.sub(r"\boffset\s+", "", line, flags=re.I)
        line = re.sub(r"^(\w+)\s+db\s+(\d+)\s+dup\((\w+)\)",
                      r"\1: times \2 db \3", line, flags=re.I)
        out.append(line)
    return "\n".join(out) + "\n"


def build(src=SRC):
    tmp = tempfile.mkdtemp()
    asm = os.path.join(tmp, "minicpu.asm")
    com = os.path.join(tmp, "minicpu.com")
    with open(src) as f:
        open(asm, "w").write(to_nasm(f.read()))
    r = subprocess.run(["nasm", "-f", "bin", "-w+all", asm, "-o", com],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr)
    return open(com, "rb").read(), r.stderr


class Screen:
    def __init__(self):
        self.clear()

    def clear(self):
        self.rows = [[" "] * 80 for _ in range(25)]
        self.r = self.c = 0

    def put(self, ch):
        if ch == 13:
            self.c = 0
        elif ch == 10:
            self.r += 1
        elif ch == 7:
            pass
        else:
            self.rows[self.r][self.c] = chr(ch)
            self.c += 1
            if self.c >= 80:
                self.c = 0
                self.r += 1
        if self.r >= 25:
            self.rows.pop(0)
            self.rows.append([" "] * 80)
            self.r = 24

    def text(self):
        return "\n".join("".join(r).rstrip() for r in self.rows).rstrip("\n")


def run(keys, max_insn=50_000_000):
    """Run the program feeding `keys`; return (screens, exited).
    screens = screen text captured every time the program waited for a key."""
    code, _ = build()
    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(0, 0x10000)
    uc.mem_write(0x100, code)
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        uc.reg_write(reg, 0)
    uc.reg_write(UC_X86_REG_SP, 0xFFFE)
    scr = Screen()
    keys = list(keys)
    screens = []
    state = {"exited": False}

    def hook(uc, intno, _):
        ax = uc.reg_read(UC_X86_REG_AX)
        ah = ax >> 8
        if intno == 0x21:
            if ah == 0x02:
                scr.put(uc.reg_read(UC_X86_REG_DX) & 0xFF)
            elif ah == 0x09:
                p = uc.reg_read(UC_X86_REG_DX)
                while True:
                    b = uc.mem_read(p, 1)[0]
                    if b == ord("$"):
                        break
                    scr.put(b)
                    p += 1
            elif ah == 0x4C:
                state["exited"] = True
                uc.emu_stop()
            else:
                raise RuntimeError("unsupported INT 21h AH=%02X" % ah)
        elif intno == 0x10:
            if ah == 0x00:
                scr.clear()
            else:
                raise RuntimeError("unsupported INT 10h AH=%02X" % ah)
        elif intno == 0x16:
            screens.append(scr.text())
            if not keys:
                uc.emu_stop()
                return
            k = keys.pop(0)
            uc.reg_write(UC_X86_REG_AX, (ax & 0xFF00) | ord(k))
        else:
            raise RuntimeError("unexpected INT %02Xh" % intno)

    uc.hook_add(UC_HOOK_INTR, hook)
    uc.emu_start(0x100, 0x10000, count=max_insn)
    return screens, state["exited"]
