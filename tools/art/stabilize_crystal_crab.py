"""Stabilize face, shell detail and contour boil with motion-matched frame votes.

No image generation, blended output colours or spatial blur. Contour changes
are confined to the original silhouette's one-pixel boundary.
Always reads the immutable input snapshot, never a previously filtered output.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import zipfile

import numpy as np
from PIL import Image

WORKSPACE = Path(__file__).resolve().parents[3]
ASSETS = WORKSPACE / 'homeing-star-game/assets/bosses/crystal_crab/body/boss/actions'
OUT = WORKSPACE / 'homeing-star-test/artifacts/crystal-crab-contours'
SOURCE = WORKSPACE / 'homeing-star-temp-assert/Art/盐场各BOSS/晶蟹/稳帧前精修PNG.zip'
ACTIONS = ['idle', 'walk', 'left_slam', 'right_slam', 'double_slam', 'burrow']
PARTS = ['START', 'ING', 'END']


def box_mean(a, radius):
    width = 2 * radius + 1
    a = np.pad(a, ((radius, radius), (radius, radius)), mode='edge')
    integral = np.pad(a, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    return (integral[width:, width:] - integral[:-width, width:]
            - integral[width:, :-width] + integral[:-width, :-width]) / width**2


def feature(a):
    f = a.astype(np.float32) / 255
    # A transparent background must not match white plates or dark joints.
    return np.stack([f[:, :, :3].mean(2) * f[:, :, 3],
                     (f[:, :, 1] - f[:, :, 0]) * f[:, :, 3],
                     f[:, :, 3]], axis=2)


def correspondence(current, neighbour):
    """Coarse patch search then integer full-resolution refinement (no warp blur)."""
    small = [np.asarray(Image.fromarray(a).resize((128, 128), Image.Resampling.BOX))
             for a in (current, neighbour)]
    a, b = map(feature, small)
    yy, xx = np.indices((128, 128))
    cost = np.full((128, 128), np.inf, np.float32)
    dx = np.zeros((128, 128), np.int32)
    dy = dx.copy()
    for sy in range(-6, 7):
        for sx in range(-6, 7):
            sample = b[np.clip(yy + sy, 0, 127), np.clip(xx + sx, 0, 127)]
            distance = box_mean(np.abs(a - sample).mean(2), 6)
            distance += (sx*sx + sy*sy) * 0.00003
            better = distance < cost
            cost[better], dx[better], dy[better] = distance[better], sx, sy
    dx = dx.repeat(2, 0).repeat(2, 1) * 2
    dy = dy.repeat(2, 0).repeat(2, 1) * 2
    a, b = feature(current), feature(neighbour)
    yy, xx = np.indices((256, 256))
    best = np.full((256, 256), np.inf, np.float32)
    bx, by = xx.copy(), yy.copy()
    for sy in range(-1, 2):
        for sx in range(-1, 2):
            tx, ty = np.clip(xx + dx + sx, 0, 255), np.clip(yy + dy + sy, 0, 255)
            sample = b[ty, tx]
            distance = box_mean(np.abs(a - sample).mean(2), 4)
            better = distance < best
            best[better], bx[better], by[better] = distance[better], tx[better], ty[better]
    # Eye rims and spikes must follow their enclosing plate, not track their
    # own one-pixel paint errors as independent motion.
    dx = np.rint(box_mean((bx-xx).astype(float), 3)).astype(int)
    dy = np.rint(box_mean((by-yy).astype(float), 3)).astype(int)
    bx, by = np.clip(xx+dx, 0, 255), np.clip(yy+dy, 0, 255)
    best = box_mean(np.abs(a-b[by,bx]).mean(2), 4)
    return bx.astype(np.int16), by.astype(np.int16), best.astype(np.float32)


def palette_snap(a, palette):
    result = a.copy()
    colors, inverse = np.unique(a[:, :, :3].reshape(-1, 3), axis=0, return_inverse=True)
    distances = ((colors.astype(np.float32)[:, None] - palette[None].astype(np.float32))**2).sum(2)
    snapped = palette[distances.argmin(1)][inverse].reshape(256, 256, 3)
    result[:, :, :3] = np.where((a[:, :, 3] > 0)[:, :, None], snapped, a[:, :, :3])
    # The authored walk ING has stray alpha=226 paint; solid plates stay solid.
    result[:, :, 3] = np.where(a[:, :, 3] > 0, 255, 0)
    return result


def lock_eye_details(original, fixed):
    """Reuse the authored eye pair only while its surrounding face matches.

    Track the face around the eyes, excluding the unstable pupils themselves.
    Never lock an occluded/turned face or copy the surrounding shell silhouette.
    """
    reference = original[0]
    patches = [(125,120,136,131),(148,122,159,133)]
    x0,y0,x1,y1 = 116,113,169,141
    ref = reference[y0:y1,x0:x1].astype(float)
    weight = np.ones(ref.shape[:2],bool)
    for a,b,c,d in patches: weight[max(0,b-y0):d-y0,max(0,a-x0):c-x0] = False
    weight &= ref[:,:,3]>0
    tracks = []
    for source in original:
        best = (float('inf'),0,0)
        for dy in range(-22,15):
            for dx in range(-12,13):
                sample = source[y0+dy:y1+dy,x0+dx:x1+dx].astype(float)
                score = np.abs(ref-sample).mean(2)[weight].mean()/255
                score += (abs(dx)+abs(dy))*.00003
                if score<best[0]: best = (score,dx,dy)
        tracks.append(best)
    count = 0
    for i,(score,dx,dy) in enumerate(tracks):
        if score>.10: continue
        # No isolated one-pixel tracking overshoot in a slow held face.
        if 0<i<len(tracks)-1:
            if abs(tracks[i-1][1]-tracks[i+1][1])==0 and abs(dx-tracks[i-1][1])==1:
                dx = tracks[i-1][1]
            if abs(tracks[i-1][2]-tracks[i+1][2])==0 and abs(dy-tracks[i-1][2])==1:
                dy = tracks[i-1][2]
        # An eye actually has to be visible at the tracked location; do not
        # paint eyes onto a claw that has moved in front of the face.
        def green_count(a):
            rgb = a[:,:,:3].astype(int)
            return int(((rgb[:,:,1]-rgb[:,:,0]>25) & (a[:,:,3]>0)).sum())
        if any(green_count(original[i][b+dy:d+dy,a+dx:c+dx]) < max(2,green_count(reference[b:d,a:c])*.35)
               for a,b,c,d in patches): continue
        for a,b,c,d in patches:
            target = fixed[i][b+dy:d+dy,a+dx:c+dx]
            eye = reference[b:d,a:c]
            mask = (target[:,:,3]>0) & (eye[:,:,3]>0)
            target[mask,:3] = eye[mask,:3]
        count += 1
    return count


def stabilize(frames, loop, action):
    yy, xx = np.indices((256, 256))
    matches = {}
    cache = OUT / 'motion'
    cache.mkdir(parents=True, exist_ok=True)
    pairs = [(i,i+1) for i in range(len(frames)-1)]
    if loop: pairs.append((len(frames)-1,0))
    for a,b in pairs:
        for j,k in [(a,b),(b,a)]:
            digest = hashlib.sha256(frames[j].tobytes()+frames[k].tobytes()+b'contour-v2').hexdigest()[:16]
            path = cache/(action+'_'+str(j)+'_'+str(k)+'_'+digest+'.npz')
            if path.exists():
                with np.load(path) as saved: matches[j,k] = (saved['x'],saved['y'],saved['cost'])
            else:
                x,y,cost = correspondence(frames[j],frames[k])
                np.savez_compressed(path,x=x,y=y,cost=cost)
                matches[j,k] = (x,y,cost)
    result, changes, contours = [], [], []
    for i,frame in enumerate(frames):
        samples = [frame]
        reliable = [np.ones((256,256),bool)]
        for direction in [-1,1]:
            x,y = xx.copy(),yy.copy()
            valid = np.ones((256,256),bool)
            previous = i
            for step in [1,2]:
                j = i+direction*step
                if not loop and not 0<=j<len(frames): break
                j %= len(frames)
                mx,my,cost = matches[previous,j]
                rx,ry,_ = matches[j,previous]
                tx,ty = mx[y,x],my[y,x]
                valid &= (np.abs(rx[ty,tx]-x)<=2) & (np.abs(ry[ty,tx]-y)<=2) & (cost[y,x]<.11)
                x,y = tx,ty
                samples.append(frames[j][y,x]); reliable.append(valid.copy())
                previous = j
        rgba = np.stack(samples)
        valid = np.stack(reliable)
        visible = (rgba[:,:,:,3]>0) & valid
        visible_votes = visible.sum(0)
        transparent_votes = ((rgba[:,:,:,3]==0) & valid).sum(0)
        opaque = frame[:,:,3]>0
        # At least three matched observations, never a single neighbour, may
        # correct silhouette chatter. Changes cannot move an edge >1 texel.
        filled = (visible_votes>=3) & (visible_votes>transparent_votes)
        erased = (transparent_votes>=3) & (transparent_votes>visible_votes)
        near_inside = box_mean(opaque.astype(float),1)>0
        near_outside = box_mean(opaque.astype(float),1)<1
        output_opaque = opaque.copy()
        output_opaque[filled & near_inside] = True
        output_opaque[erased & near_outside] = False
        # Select a medoid from actual palette pixels: no interpolated smearing.
        rgb = rgba[:,:,:,:3].astype(np.float32)
        score = np.zeros(valid.shape,np.float32)
        for k in range(len(samples)):
            distances = np.minimum(np.abs(rgb-rgb[k]).mean(3),80)
            score[k] = (distances*visible).sum(0)/np.maximum(visible_votes,1)
        score[~visible] = 1e6
        # Prefer the authored current pixel when votes are tied.
        score[0] -= 2.0
        pick = score.argmin(0)
        choice = rgba[pick,yy,xx]
        chosen_score = np.take_along_axis(score,pick[None],axis=0)[0]
        difference = np.abs(choice[:,:,:3].astype(int)-frame[:,:,:3].astype(int)).mean(2)
        consistent = (visible_votes>=3) & (chosen_score<29) & (difference>9)
        # Two-sided support avoids repainting moving/occluding parts from a
        # single old pose at an attack boundary.
        if len(samples)==5:
            support = (np.abs(rgb-choice[None,:,:,:3]).mean(3)<22) & visible
            consistent &= support.sum(0)>=3
        else:
            consistent &= (visible_votes>=len(samples))
        fixed = frame.copy()
        replace = (consistent | (~opaque & output_opaque)) & output_opaque
        fixed[replace,:3] = choice[replace,:3]
        fixed[:,:,3] = np.where(output_opaque,255,0)
        fixed[~output_opaque,:3] = 0
        result.append(fixed)
        changes.append(int((replace & opaque).sum()))
        contours.append({'filled':int((~opaque & output_opaque).sum()),
                         'removed':int((opaque & ~output_opaque).sum())})
    return result,changes,contours


def preview(frames, path):
    images = [Image.alpha_composite(Image.new('RGBA', (256,256), (42,48,58,255)),
                                   Image.fromarray(f)).convert('RGB').resize((512,512), Image.Resampling.NEAREST)
              for f in frames]
    images[0].save(path, save_all=True, append_images=images[1:], duration=100, loop=0, disposal=2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    snapshot = SOURCE
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    if not snapshot.exists():
        with zipfile.ZipFile(snapshot, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(ASSETS.glob('*.png')): archive.write(path, path.name)
    report = {}
    with zipfile.ZipFile(snapshot) as archive:
        for action in ACTIONS:
            frames, sizes, original = [], [], []
            for part in PARTS:
                strip = Image.open(io.BytesIO(archive.read(action+'_'+part+'.png'))).convert('RGBA')
                cells = [np.array(strip.crop((x,0,x+256,256))) for x in range(0,strip.width,256)]
                sizes.append(len(cells)); original += cells
            # Keep each action's hand-refined colours; only walk's stray blended
            # ING colours are snapped to that same action's own START palette.
            base = original[0]
            palette = np.unique(base[:,:,:3][base[:,:,3]>0],axis=0)
            frames = [palette_snap(f,palette) if action=='walk' else f.copy() for f in original]
            if action!='walk':
                palette = np.unique(np.concatenate([f[:,:,:3][f[:,:,3]>0] for f in original]),axis=0)
            fixed, changes, contours = stabilize(frames, action in ('idle', 'walk'),action)
            locked_eyes = lock_eye_details(frames,fixed)
            for a,b in zip(original,fixed):
                edge = (box_mean((a[:,:,3]>0).astype(float),1)>0) & (box_mean((a[:,:,3]>0).astype(float),1)<1)
                assert not np.any(((a[:,:,3]>0)!=(b[:,:,3]>0)) & ~edge)
            assert all(np.isin(f[:,:,:3][f[:,:,3]>0].copy().view('V3'), palette.copy().view('V3')).all() for f in fixed)
            offset = 0
            for part, count in zip(PARTS, sizes):
                target = ASSETS if args.apply else OUT / 'candidate'
                target.mkdir(parents=True, exist_ok=True)
                Image.fromarray(np.concatenate(fixed[offset:offset+count],axis=1)).save(target/(action+'_'+part+'.png'))
                offset += count
            report[action] = {'temporal_corrected_pixels': changes,
                              'total_corrected': sum(changes),
                              'changed_rgba': [int(np.any(a!=b,axis=2).sum()) for a,b in zip(original,fixed)],
                              'contour_corrections':contours, 'max_contour_correction_texels':1,
                              'face_matched_eye_template_frames':locked_eyes,
                              'output_sha256':{part:hashlib.sha256((target/(action+'_'+part+'.png')).read_bytes()).hexdigest() for part in PARTS}}
            preview(original, OUT/(action+'_before.gif'))
            preview(fixed, OUT/(action+'_after.gif'))
            print(action, report[action], flush=True)
    (OUT/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    if args.apply:
        path = ASSETS/'library.json'
        manifest = json.loads(path.read_text(encoding='utf-8'))
        manifest['postprocess'] = {'tool':'homeing-star-test/tools/art/stabilize_crystal_crab.py',
                                   'source_snapshot':str(SOURCE.relative_to(WORKSPACE)),
                                   'method':'five-frame integer motion-matched medoid, face/back/one-texel contour correction',
                                   'authored_action_palettes':True,'timing_and_ground_unchanged':True,'actions':report}
        path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__': main()
