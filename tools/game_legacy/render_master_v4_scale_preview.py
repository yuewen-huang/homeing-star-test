from pathlib import Path
from PIL import Image, ImageDraw

hero_sheet = Image.open(r"D:\homing-star-godot\assets\sideview\characters\lan\idle.png").convert("RGBA")
hero = hero_sheet.crop((0, 0, 46, 55))
master = Image.open(r"D:\homing-star-godot\PendingArt\character\师傅\像素母版-v2\师傅-一阶段-巨剑母版-192x128-低密度20色-v4.png").convert("RGBA")
out_path = Path(r"D:\homing-star-godot\PendingArt\character\师傅\像素母版-v2\主角与师傅-低密度重绘比例对比-v4.png")
preview = Image.new("RGBA", (300, 144), (32, 37, 42, 255))
baseline = 132
preview.alpha_composite(hero, (38, baseline - 55))
preview.alpha_composite(master, (100, baseline - 124))
d = ImageDraw.Draw(preview)
d.line((0, baseline, 300, baseline), fill=(100, 112, 122, 255), width=1)
d.text((34, 8), "LAN 46x55", fill=(220, 224, 228, 255))
d.text((150, 8), "MASTER clean 20c", fill=(220, 224, 228, 255))
preview.resize((900, 432), Image.Resampling.NEAREST).save(out_path)
print(out_path)
