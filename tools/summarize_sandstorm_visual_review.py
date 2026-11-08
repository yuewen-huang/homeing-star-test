"""Post-run contact sheets; never feeds gameplay controls."""
from pathlib import Path
from PIL import Image, ImageDraw

out = Path(__file__).resolve().parents[1] / 'artifacts/sandstorm-visual-review'
for start, end in [(20, 31), (32, 43), (44, 55), (56, 67), (68, 73)]:
    sheet = Image.new('RGB', (1920, 4 * 300 if end-start > 11 else 3 * 300), '#17191b')
    draw = ImageDraw.Draw(sheet)
    for i, second in enumerate(range(start, end + 1)):
        path = out / 'frames' / f'frame_{second * 15 - 1:05d}.png'
        frame = Image.open(path).convert('RGB').resize((480, 270))
        x, y = (i % 4) * 480, (i // 4) * 300
        sheet.paste(frame, (x, y + 25))
        draw.text((x + 8, y + 6), f'{second:.2f}s simulation / 1x timeline', fill='white')
    sheet.save(out / f'contact_{start:02d}_{end:02d}.jpg', quality=94)
