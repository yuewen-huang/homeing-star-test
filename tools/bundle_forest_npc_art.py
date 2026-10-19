"""Bundle only the newly produced forest NPC resources and their gallery."""
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'homeing-star-game'
ART = ROOT / 'homeing-star-temp-assert/PendingArt/forest_npcs/20261015-production'
folders = [GAME / 'assets/characters/forest_npcs', GAME / 'assets/shared/ui/portraits/forest_npcs']
folders += [GAME / 'assets/shared/ui/portraits/dialogue_fit' / x for x in ['yupo', 'ali', 'lingwei', 'xiaosui']]
files = [p for f in folders for p in f.rglob('*') if p.is_file()]
files += [GAME / 'scenes/dev/forest_npc_art_gallery.tscn', GAME / 'scripts/dev/forest_npc_art_gallery.gd',
          GAME / 'scripts/dev/forest_npc_art_gallery.gd.uid']
with zipfile.ZipFile(ART / 'forest_npcs_runtime_assets.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, path.relative_to(GAME).as_posix())
evidence = ART / 'godot_preview'
evidence.mkdir(exist_ok=True)
test_run = ROOT / 'homeing-star-test/artifacts/20261015-122852-954'
for name in ['forest_npcs_frame_00.png', 'forest_npcs_frame_02.png', 'forest_npc_lingwei_left.png',
             'forest_npc_yupo_right.png', 'test_forest_npc_art.log', 'test_forest_npc_art.errors.log']:
    shutil.copyfile(test_run / name, evidence / name)
print(f'Bundled {len(files)} files; copied representative Godot evidence.')
