from pathlib import Path
import argparse, copy, hashlib, json, shutil
from PIL import Image, ImageDraw, ImageFont
from package_deer_vfx_aseprite import write_aseprite, composite, LAYERS


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    out = args.output
    old = out.parent / 'deer-root-concepts-20261010'
    manifest = json.loads((out / 'capture_manifest.json').read_text(encoding='utf-8'))
    previous = json.loads((old / 'capture_manifest.json').read_text(encoding='utf-8'))
    clips = [c for c in manifest['clips'] if c['id'] in ('heavy_single', 'tracking_short', 'tide_tile', 'decoy_cluster')]
    resource = Path('D:/HomingStar/homing-star-godot/assets/sideview/effects/deer_painted/timelines.tres').read_text(encoding='utf-8')
    timeline = json.loads(json.loads(resource.split('metadata/timelines = ', 1)[1].strip()))

    def extract(source_id, clip_id, name, indices, effect_origin, back_only=False):
        source = next(c for c in previous['clips'] if c['id'] == source_id)
        raw = out / 'raw' / clip_id
        raw.mkdir(parents=True, exist_ok=True)
        clip = {'id': clip_id, 'name': name, 'folder': str(raw), 'canvas': source.get('canvas', previous.get('canvas', [512,384])), 'anchor': source.get('anchor', previous.get('anchor', [256,332])), 'effect_origin': effect_origin, 'frames': []}
        for dest_index, source_index in enumerate(indices):
            frame = copy.deepcopy(source['frames'][source_index])
            frame.update(index=dest_index, duration_ms=50, source_index=source_index, source_clip=source_id, source_time_ms=source_index*50, concept_only=True)
            if back_only:
                frame['stage'] = '到达鹿蹄_失衡起势' if source_index == 177 else '根力回流'
            else:
                frame['stage'] = '根瘤拱起' if dest_index < 3 else ('完全长出_复用此帧保持' if dest_index == 3 else ('退场完成' if dest_index == len(indices)-1 else '根瘤回收'))
            for layer in ('back', 'body', 'front', 'warning'):
                target = raw / f'{dest_index:04d}_{layer}.png'
                if back_only and layer in ('front', 'warning'):
                    Image.new('RGBA', clip['canvas']).save(target)
                else:
                    shutil.copyfile(Path(source['folder']) / f'{source_index:04d}_{layer}.png', target)
            if not back_only:
                offsets = timeline['clips']['light_stomp'].get('body_offsets', [])
                matches = [r for r in offsets if r['animation'] == frame['animation'] and r['body_frame'] == frame['body_frame']]
                if matches:
                    chosen = min(matches, key=lambda r: abs(r['time_ms'] - source_index*50))
                    shift = tuple(map(int, chosen['offset']))
                    frame['body_reference_offset_pixels'] = list(shift)
                    image = Image.open(raw / f'{dest_index:04d}_body.png').convert('RGBA')
                    aligned = Image.new('RGBA', clip['canvas'])
                    aligned.paste(image, shift)
                    aligned.save(raw / f'{dest_index:04d}_body.png')
            clip['frames'].append(frame)
        clips.append(clip)

    extract('light_nodule', 'light_short', '01_根轻击_根瘤变化', [12,13,14,15,132,133,134,135,136,137], [204,332])
    extract('decoy_counter', 'return_short', '06_破解反噬_根力回流', list(range(171,178)), [811,332], back_only=True)
    clips.sort(key=lambda c: c['name'])
    previews = out / '预览'
    previews.mkdir(exist_ok=True)
    overview = Image.new('RGB', (1536, 960), (32,36,39))
    draw = ImageDraw.Draw(overview)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
    notes = []
    for i, clip in enumerate(clips):
        raw = Path(clip['folder'])
        selected = []
        last_digest = None
        for frame in clip['frames']:
            digest = hashlib.sha256()
            for layer in ('back','front','warning'):
                with Image.open(raw / f"{frame['index']:04d}_{layer}.png") as im:
                    digest.update(im.convert('RGBA').tobytes())
            current = digest.digest()
            if current != last_digest:
                selected.append(frame)
            last_digest = current
        clip['frames'] = selected
        elapsed = 0
        for frame in selected:
            frame['time_ms'] = elapsed
            elapsed += frame['duration_ms']
        filename = clip['name'] + '.aseprite'
        tags = write_aseprite(out / filename, selected, raw, clip['canvas'], clip['anchor'])
        notes.append({k: clip[k] for k in ('id', 'canvas', 'anchor', 'effect_origin')} | {'file': filename, 'frame_count': len(selected), 'duration_ms':elapsed, 'tags':tags, 'frames':selected})
        rendered = []
        for frame in selected:
            bg = Image.new('RGBA', clip['canvas'], (32,36,39,255))
            bg.alpha_composite(composite(raw, frame, clip['canvas']))
            if bg.width > 1024:
                bg = bg.resize((1024, round(bg.height * 1024/bg.width)), Image.Resampling.NEAREST)
            rendered.append(bg.convert('RGB'))
        rendered[0].save(previews / (clip['name']+'.gif'), save_all=True, append_images=rendered[1:], duration=[f['duration_ms'] for f in selected], loop=0, disposal=2)
        def area(frame):
            box = Image.open(raw / f"{frame['index']:04d}_front.png").getbbox()
            return (box[2]-box[0])*(box[3]-box[1]) if box else 0
        peak = len(selected)//2 if clip['id'] == 'return_short' else max(range(len(selected)), key=lambda j:area(selected[j]))
        rendered[peak].save(previews / (clip['name']+'_峰值.png'))
        thumb = rendered[peak].copy()
        thumb.thumbnail((480,400), Image.Resampling.NEAREST)
        x, y = i%3*512, i//3*480
        overview.paste(thumb, (x+(512-thumb.width)//2, y+65+(400-thumb.height)//2))
        draw.text((x+16,y+10), clip['name'], font=font, fill=(235,238,240))
        draw.text((x+16,y+36), f'{len(selected)} 帧 / {elapsed} ms', font=font, fill=(169,183,194))
        print(filename, len(selected), 'frames', elapsed, 'ms', flush=True)
    overview.save(previews / '短段总览.png')
    manifest['clips'] = clips
    manifest['status'] = 'concept_only_unique_segments'
    (out / 'capture_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    (out / '时间轴.json').write_text(json.dumps({'status':manifest['status'], 'world_units_per_pixel':1.4, 'layers':[l[0] for l in LAYERS], 'clips':notes}, ensure_ascii=False, indent=2), encoding='utf-8')
    total = sum(n['frame_count'] for n in notes)
    table = '\n'.join(f"| {n['file']} | {n['frame_count']} |" for n in notes)
    readme = f'''# 根阶段：只画这些变化

本次从旧版 844 帧精简为 {total} 帧，分为六个短段。根轻击、根重击拥有自己的特效；鹿本体动作可以复用雾阶段，根阶段特效需要重新画。这里只删除重复段、长保持和重复轮次。

| 文件 | 帧数 |
|---|---|
{table}

## 最终只画四类素材

矮树根、中树根、高树根、根瘤。树根各画一根的破土、最高形态和回收；根瘤画长出、常驻和击碎。根阶段取消冲刺上挑，鹿的跺脚、重踩、鹿鸣和失衡复用已有本体动作。

| 要画的素材 | 现有 Aseprite 参考 | 复用位置 |
|---|---|---|
| 矮树根 | 02 单根破土 | 重踩根浪、根簇两侧 |
| 中树根 | 03 中间的一根，两边只看摆位 | 追踪根簇、根瘤出根击飞、破解集束 |
| 高树根 | 04 任意一根，其余只看摆位 | 全场根潮、破解集束中心 |
| 根瘤 | 01 根瘤变化 | 永久地面陷阱，两次普攻击碎 |

不用把一排、一簇、六轮或整场分别画出来。05 是矮—中—高—中—矮的程序组合参考；06 回流用现有裂纹／碎土素材加程序位移和闪烁，不要求另外绘制。分身使用岚现有轮廓，预警和碎土复用已有素材。

矮／中／高的参考高度约为 72／90／224 世界单位，尺寸与最终判定以你画的为准。第一击根瘤受损先用程序闪烁，不增加独立破损素材。

## 六份工程怎么作为参考

1. **根轻击／根瘤变化**：根瘤拱起、最高形态、击碎退场。最高形态永久保持时复用一帧或你画的少量循环帧，不铺满等待时间轴；后半段收回只作为击碎退场的占位参考。根瘤需要两次普攻击碎，跑过时概率出根击飞。触发树根复用中树根的破土与回收，跳过预警并对齐根瘤中心；树根收回后根瘤仍在。保留鹿落蹄和收势的真实姿势参考，已应用现有轻击本体对齐。
2. **根重击／单根破土**：裂纹预警、单根上冲、收回、裂缝消退。八根连续根浪由程序排列，首根距鹿 120 世界单位，后续间距 64，每根错开 0.09 秒；只画这一根，不再画完整八根波。
3. **追踪根簇／单轮变化**：只画中间一根作为中树根。两侧矮根复用 02，三根一簇与六轮由程序组合，不重复画。
4. **全场根潮／单块变化**：任选一根作为高树根参考。其余根与全场排列都由程序复用，不另画高根簇。
5. **破解终击／聚向分身**：只看摆位，矮—中—高—中—矮由程序组合，不再绘制独立五根集束。分身复用现有角色轮廓。
6. **破解反噬／根力回流**：只看流程，不要求另画。地下回流复用已有裂纹／碎土素材，由程序移动和闪烁表现；鹿复用受击动作。

根阶段快快慢不单独导出，复用根阶段 01、01、02 的特效。根阶段取消冲刺上挑。鹿鸣、蓄势、收势、待机和受击本体都不用再画。

## 画布、图层和时间

- 01—05：透明画布 512×384，鹿脚底原点 (256,332)。02—05 的地面效果中心为 (113,332)，鹿只用于看比例；正式游戏里的地面位置由程序独立安排。01 根瘤中心约 (204,332)。
- 06：透明画布 2048×384，鹿脚底原点 (1740,332)，回流起点 (811,332)。这里保留宽画布是为了展示唯一的回流路线，不包含多轮重复动作。
- 1 画布像素对应 1.4 世界单位；所有文件带 boss_origin 切片定位。
- 在 **绘制_前景、绘制_后景** 空白独立帧上画，概念层、动作层和预警层均为可隐藏参考。参考图层不要当正式素材导出。
- 时间轴已经缩短，保持段只留最高帧，短段不代表完整招式总时长。时间轴 JSON 保存原采样时间和精简帧时长；正式播放再接回完整动作时间。
- GIF 的深色底仅用于预览，Aseprite 仍透明。正式特效的形状、范围和帧数以你画的为准。

这些仍是专用 BOSS 调试房采样的概念绘制工程，根阶段战斗机制和雾分身道具待接入，AI 最后做。旧工程与已绘制的雾阶段素材保持原样。
'''
    (out / '只画这些变化.md').write_text(readme, encoding='utf-8')
    print('TOTAL', total, 'frames in', len(clips), 'files', flush=True)

if __name__ == '__main__':
    main()
