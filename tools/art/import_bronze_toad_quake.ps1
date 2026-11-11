$ErrorActionPreference = 'Stop'
$workspace = Join-Path $PSScriptRoot '../../..'
$source = Join-Path $workspace 'combat-vfx-studio/combos/bronze_toad_fracture/combo.json'
$target = Join-Path $workspace 'homeing-star-game/assets/levels/chapter_2_underwater/cavern/boss/bronze_toad/fracture_quake.json'
$score = Get-Content -Raw -LiteralPath $source | ConvertFrom-Json
if ($score.events.Count -ne 2 -or $score.events[0].body -or -not $score.events[1].body -or
    ($score.events | Where-Object { $_.do -ne 'quake' -or $_.unit -ne 'earth' -or $_.shake -ne 0 })) {
    throw 'Expected a Studio ground crack and earth surge with camera shake handled by the room.'
}
Copy-Item -LiteralPath $source -Destination $target
