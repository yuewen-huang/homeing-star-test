"""Union the accepted procedural geometry. Deliberately discard every armor facet."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
FOLDER = ROOT / 'combat-vfx-studio/studies/sandstorm_scorpion'
data = json.loads((FOLDER / 'ghost.json').read_text(encoding='utf-8'))
mask = Image.new('L', (440, 460))
draw = ImageDraw.Draw(mask)
for shape in data['shapes']:
    draw.polygon([(x+60, y+40) for x,y in shape['points']], fill=255)
# Linear data channels: close silhouette, nearby suspended dust, wider dust veil.
Image.merge('RGBA', (mask.filter(ImageFilter.GaussianBlur(.8)),
                    mask.filter(ImageFilter.GaussianBlur(3.0)),
                    mask.filter(ImageFilter.GaussianBlur(8.0)), mask)).save(FOLDER/'sand_mask.png')
print('Created silhouette-only mask from accepted polygon union: 440 x 460')
