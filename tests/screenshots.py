"""Render simulator screens (from the test emulator) to PNG for the README."""
import os
from PIL import Image, ImageDraw, ImageFont
from dosemu import run

OUT = os.path.join(os.path.dirname(__file__), "..", "screenshots")
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 26)

def render(text, name, rows=25):
    cw, ch = FONT.getbbox("M")[2], 34
    img = Image.new("RGB", (cw * 80 + 40, ch * rows + 40), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, l in enumerate(text.splitlines()[:rows]):
        color = (192, 192, 192)
        s = l.strip()
        if s.startswith(("Stage", "Action", "Signals")):
            color = (255, 255, 120)
        if s.startswith(("OUTPUT", "***")):
            color = (120, 255, 120)
        if s.startswith(("MINI CPU", "INSTRUCTION SET", "PROGRAM LISTING")):
            color = (120, 200, 255)
        d.text((20, 20 + i * ch), l, font=FONT, fill=color)
    img.save(os.path.join(OUT, name))

s, _ = run("")
render(s[-1], "01_menu.png", 16)
s, _ = run("3")
render(s[-1].strip("\n"), "02_listing.png", 20)
s, _ = run("1 \r\r\r\r")           # LOAD R1,30h(R0) - stage 4 MEMORY
render(s[-1], "03_stage_memory.png", 22)
s, _ = run("3 R")
render(s[-1], "04_demo3_halt.png", 22)
s, _ = run("5")
render(s[-1], "05_instruction_set.png", 22)
print(sorted(os.listdir(OUT)))
