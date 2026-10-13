"""Read RGBA Aseprite raster layers without changing native sources.

Normal, ungrouped layers and raw/compressed/linked cels are supported. Unsupported
blend modes, groups, tilemaps or cel z-order fail explicitly rather than losing art.
"""
import struct
import zlib
from PIL import Image


def read(path):
    raw = path.read_bytes()
    size, magic, count, width, height, depth = struct.unpack_from('<I5H', raw)
    if magic != 0xA5E0 or depth != 32 or size != len(raw):
        raise ValueError('Expected a complete RGBA Aseprite document')
    offset = 128
    layers, frames = [], []
    for _ in range(count):
        length, magic, chunks, duration = struct.unpack_from('<I3H', raw, offset)
        if magic != 0xF1FA or not duration:
            raise ValueError('Invalid native frame')
        position = offset + 16
        cels = {}
        for _ in range(struct.unpack_from('<I', raw, offset + 12)[0] or chunks):
            length_chunk, kind = struct.unpack_from('<IH', raw, position)
            body = raw[position + 6:position + length_chunk]
            if kind == 0x2004:
                flags, layer_type, level, _, _, blend, opacity = struct.unpack_from('<6HB', body)
                n = struct.unpack_from('<H', body, 16)[0]
                if layer_type != 0 or level != 0 or blend != 0:
                    raise ValueError('Only ungrouped normal raster layers are supported')
                layers.append({'name': body[18:18+n].decode('utf-8'), 'visible': bool(flags & 1), 'opacity': opacity})
            elif kind == 0x2005:
                index, x, y, opacity, cel_type = struct.unpack_from('<HhhBH', body)
                if struct.unpack_from('<h', body, 9)[0] != 0:
                    raise ValueError('Cel z-order must be exported by a native renderer')
                if cel_type in (0, 2):
                    w, h = struct.unpack_from('<HH', body, 16)
                    pixels = zlib.decompress(body[20:]) if cel_type == 2 else body[20:]
                    image = Image.frombytes('RGBA', (w, h), pixels)
                elif cel_type == 1:
                    linked = struct.unpack_from('<H', body, 16)[0]
                    image = frames[linked]['cels'][index]['image'].copy()
                else:
                    raise ValueError('Unsupported tilemap cel')
                cels[index] = {'image': image, 'position': (x, y), 'opacity': opacity}
            position += length_chunk
        frames.append({'duration_ms': duration, 'cels': cels})
        offset += length
    return {'canvas': (width, height), 'layers': layers, 'frames': frames}


def layer_frame(document, frame, layer):
    """Return authored RGBA pixels and separate cel/layer opacity (no alpha baking)."""
    canvas = Image.new('RGBA', document['canvas'])
    cel = document['frames'][frame]['cels'].get(layer)
    if cel is None:
        return canvas, 0.0
    x, y = cel['position']
    w, h = cel['image'].size
    if x < 0 or y < 0 or x+w > canvas.width or y+h > canvas.height:
        raise ValueError('Cel exceeds authored canvas; refuse implicit clipping')
    canvas.paste(cel['image'], (x, y))
    opacity = cel['opacity'] / 255 * document['layers'][layer]['opacity'] / 255
    return canvas, opacity
