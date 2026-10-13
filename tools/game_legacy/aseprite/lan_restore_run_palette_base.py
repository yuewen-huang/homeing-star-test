"""Restore only the run palette base, preserving a recoverable copy first."""
from __future__ import annotations

import ast
from datetime import datetime
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CHARACTER = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a")
SOURCE = CHARACTER / "run" / "sprite sheets" / "run.png"
DESTINATION = CHARACTER / "palette-bases" / "run" / "sprite sheets" / "run.png"

tree = ast.parse((ROOT / "tools" / "aseprite" / "lan_batch_palette_bases.py").read_text(encoding="utf-8"))
PALETTE = next(
    ast.literal_eval(node.value)
    for node in tree.body
    if isinstance(node, ast.Assign)
    and any(isinstance(target, ast.Name) and target.id == "PALETTE" for target in node.targets)
)

if DESTINATION.exists():
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = DESTINATION.with_name(f"run-before-restore-{stamp}.png")
    Image.open(DESTINATION).convert("RGBA").save(backup)
    print(f"BACKUP: {backup.name}")

source = Image.open(SOURCE).convert("RGBA")
restored = source.copy()
for y in range(source.height):
    for x in range(source.width):
        r, g, b, a = source.getpixel((x, y))
        if a and (target := PALETTE.get(f"{r:02X}{g:02X}{b:02X}")):
            restored.putpixel((x, y), tuple(bytes.fromhex(target)) + (a,))

restored.save(DESTINATION)
assert restored.size == source.size
assert restored.getchannel("A").tobytes() == source.getchannel("A").tobytes()
print(f"RESTORED: {DESTINATION.name}, {restored.width}x{restored.height}")
