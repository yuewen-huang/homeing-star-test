# 镜湖 AI 生图记录 / Mirror Lake AI art log

Tool: Grok Bot `GenerateImage` (1280x720 JPG only; no seed, so every call is a "lottery draw").
Each segment was drawn 3 times (c1..c3), all viewed, one winner picked. `sources/` keeps the winners
plus the runner-ups the pipeline still uses or that are good fallbacks. The full candidate set (44 images) lives
outside the repo (box: /workspace/mirror_lake/candidates/).

## Shared style brief (prefix of every prompt)
Traditional Chinese ink-wash painting (水墨), aged off-white xuan paper (宣纸) background, ink grays and blacks,
dry brush and wet wash, ONE small cinnabar-red (朱砂) accent at most, generous empty space (留白) and drifting mist,
no people, no modern objects, no frame or border, no text (an optional tiny red seal is allowed).
Vignette segments: "isolated on plain paper, large margins on all sides, subject sits on a flat waterline at the
bottom" so the pipeline can lift the ink into an alpha layer (multiply -> alpha) without any visible box.
Far panoramas: "wide misty distant mountain range, low contrast, fading into pale mist at the bottom".

## Segments and picks (subject column is a summary; exact prompt wording was not archived)
| key | layer | subject | winner | alternates |
|---|---|---|---|---|
| far1 | 02 far | misty mountain range, peaks left | c2 | c1, c3 |
| far2 | 02 far | softer, lower ridges with mist valleys | c2 | c1, c3 |
| far3 | 02 far | very calm, low, mostly mist (boss end) | c3 | c1, c2 |
| mid1 | 03 mid | gnarled pine on rock | c3 | c2 |
| mid2 | 03 mid | bamboo grove | c3 | c1 |
| mid3 | 03 mid | pavilion (亭) on a bank | c3 | c1 |
| mid4 | 03 mid | fishing boat with awning | c3 | c1 |
| mid5 | 03 mid | arched stone bridge | c2 | – |
| mid6 | 03 mid | pillar rocks (奇石) | c3 | c1 |
| mid7 | 03 mid | weeping willow | c3 | c2 |
| mid8 | 03 mid | boss landmark: two-storey tower on an islet | c2 | – |
| g1 | 04 ground | foreground rocks / bank | c2 | c3 |
| g2 | 04 ground | reeds (芦苇) | c1 | c2, c3 |
| g3 | 04 ground | stepping-stone slabs | c3 | c2 |

## Post-processing (see build_mirror_lake_art.py)
- JPG -> grayscale ink alpha (paper estimated by a max-filter, `alpha = 1 - ink/paper`), recoloured to the map's ink colour;
  colour (green moss etc.) is dropped on purpose so every segment shares one ink tone.
- Baked-in water/reflections in boat, bridge and landmark are cut at a per-sprite base row; each sprite sits on y=555.
- Far panoramas are cross-faded (cosine ramps) into one strip; no segment repeats twice in a row (asserted).
- 阴 half: flipped, tone-inverted, darkened and ripple-distorted copy + procedural perspective water band.
