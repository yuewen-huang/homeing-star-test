"""Crop actual Godot captures into a before/after board; never edit game artwork."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT=Path(__file__).resolve().parents[1]/'artifacts/deer-phase-atmosphere-20261016'
board=Image.new('RGB',(1470,778),'#242b33')
draw=ImageDraw.Draw(board)
for column,label in enumerate(('MIST','ROOT','WIND')):
    for row,state in enumerate(('off','on')):
        im=Image.open(OUT/f'godot/phase{column+1}_idle_{state}.png').crop((540,205,1030,570)).convert('RGB')
        board.paste(im,(column*490,row*389+24))
        draw.text((column*490+12,row*389+5),label+(' / BEFORE' if state=='off' else ' / ATMOSPHERE'),fill='white')
board.save(OUT/'phase_comparison.png')
print(OUT/'phase_comparison.png')
