"""Normalize a whole authored action against its known standing reference frame.

Never fit individual frames: rolls, crouches, jumps and sword reach retain their motion.
The master pack's nine clips all begin with the same standing pose as idle.
"""
from math import ceil
from PIL import Image

def normalize(frames, idle_frame, idle_world_scale, margin=8):
    reference = idle_frame.getbbox()
    standing = frames[0].getbbox()
    assert reference and standing, 'Standing reference cannot be transparent'
    factor = (reference[3] - reference[1]) / (standing[3] - standing[1])
    w,h = frames[0].size
    size = (ceil(w*factor), ceil(h*factor))
    # One isotropic nearest-neighbour transform for every frame in the action.
    scaled = [frame.transform(size, Image.Transform.AFFINE,
              (1/factor,0,0,0,1/factor,0), Image.Resampling.NEAREST) for frame in frames]
    boxes = [im.getbbox() for im in scaled if im.getbbox()]
    left = min(b[0] for b in boxes)-margin
    top = min(b[1] for b in boxes)-margin
    right = max(b[2] for b in boxes)+margin
    bottom = max(b[3] for b in boxes)+margin
    width = ceil((right-left)/8)*8
    height = ceil((bottom-top)/8)*8
    crop = (left,top,left+width,top+height)
    result = [frame.crop(crop) for frame in scaled]
    first = result[0].getbbox()
    # Preserve idle's current world registration, including its small x asymmetry.
    idle_left = reference[0] - idle_frame.width/2
    feet = [first[0]-idle_left, first[3]]
    report = {'source_cell':[w,h], 'pixel_scale':factor, 'crop_origin':[left,top],
              'reference_frame':0, 'reference_body_height':reference[3]-reference[1],
              'rendered_body_height':(first[3]-first[1])*idle_world_scale,
              'world_scale':idle_world_scale, 'margin':margin}
    assert first[3]-first[1] == reference[3]-reference[1], report
    return result, feet, report
