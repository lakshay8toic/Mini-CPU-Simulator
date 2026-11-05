"""Render the simulator's screen (from the test emulator) to PNG for the README."""
import os
from PIL import Image, ImageDraw, ImageFont
from dosemu import run

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "screenshots")
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 24)


def render(text, name):
    lines = text.splitlines()
    cw, ch = FONT.getbbox("M")[2], 32
    img = Image.new("RGB", (cw * 64 + 40, ch * len(lines) + 40), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, l in enumerate(lines):
        color = (200, 200, 200)
        s = l.strip()
        if s.startswith("[FETCH]"):
            color = (120, 200, 255)
        elif s.startswith("[DECODE]"):
            color = (255, 220, 110)
        elif s.startswith("[EXECUTE]"):
            color = (130, 255, 130)
        elif s.startswith(("=", "Result")):
            color = (255, 150, 150)
        d.text((20, 20 + i * ch), l, font=FONT, fill=color)
    img.save(os.path.join(OUT, name))


os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    os.remove(os.path.join(OUT, f))
s, _ = run("   ")                    # first instruction : fetch, decode, execute
render(s[-1].rstrip("-\n ").rstrip(), "01_first_instruction.png")
s, _ = run(" " * 100)                # whole program finished
render(s[-1], "02_program_finished.png")
print(sorted(os.listdir(OUT)))
