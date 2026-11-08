"""Package native captures without changing exposure or playback speed."""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument('--name', choices=['sand_grain', 'sand_balanced'], default='sand_grain')
name = parser.parse_args().name
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'homeing-star-test/artifacts/sandstorm-scorpion-study'
FRAMES = OUT / 'apparition'
board = Image.new('RGB', (1200, 720), '#202523')
draw = ImageDraw.Draw(board)
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 17)
for i, number in enumerate([12, 24, 39, 51, 63, 78, 87, 96, 108]):
    im = Image.open(FRAMES / f'frame_{number:03d}.png').crop((340,40,940,700)).resize((200,220))
    x, y = (i % 3)*400+100, (i//3)*240
    board.paste(im, (x,y))
    draw.text((x-70,y+12), f'{number/30:.1f}s', font=font, fill='#d7bc8f')
board.save(OUT/f'{name}_review.png')
Image.open(FRAMES/'frame_045.png').crop((340,40,940,700)).save(OUT/f'{name}_formed.png')
frames = [Image.open(FRAMES/f'frame_{n:03d}.png').crop((270,20,1010,700)) for n in range(0,133,2)]
frames[0].save(OUT/f'{name}_apparition.gif', save_all=True, append_images=frames[1:],
               duration=[60 if i%3==0 else 70 for i in range(len(frames))], loop=0, optimize=False)
print('Saved grain review and preview; full video remains 30 FPS.')
