param(
    [string]$Godot = 'E:/Godot Hub/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe',
    [switch]$CounterUpslash,
    [switch]$CounterSlash,
    [switch]$TurningUppercut,
    [switch]$TripleJumpSlash,
    [switch]$RaiseAndReturn
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$game = Join-Path $workspace 'homeing-star-game'
$preview = Join-Path $PSScriptRoot 'preview_sunken_general.gd'
$atlas = Join-Path $workspace 'homeing-star-temp-assert/PendingArt/sunken_general/20261112/stance/two_handed_sweep/motion/recovery/step_in_sweep_520x350_19f.png'
$animationArgument = $null
if ($RaiseAndReturn) {
    $atlas = Join-Path $workspace 'homeing-star-temp-assert/PendingArt/sunken_general/20261112/stance/front_guandao_stand/raise_and_return/motion/raise_and_return_520x350_16f.png'
    $animationArgument = '--raise-and-return'
} elseif ($TripleJumpSlash) {
    $atlas = Join-Path $workspace 'homeing-star-temp-assert/PendingArt/sunken_general/20261112/stance/triple_jump_slash/motion/triple_jump_slash_520x350_33f.png'
    $animationArgument = '--triple-jump-slash'
} elseif ($TurningUppercut) {
    $atlas = Join-Path $workspace 'homeing-star-temp-assert/PendingArt/sunken_general/20261112/stance/low_stance_uppercut/turning/motion/turning_uppercut_520x350_20f.png'
    $animationArgument = '--turning-uppercut'
} elseif ($CounterSlash) {
    $atlas = Join-Path $workspace 'homeing-star-temp-assert/PendingArt/sunken_general/20261112/stance/counter_slash_video/motion/registration/reverse_slash_520x350_20f.png'
    $animationArgument = '--counter-slash'
} elseif ($CounterUpslash) {
    $atlas = Join-Path $workspace 'homeing-star-temp-assert/PendingArt/sunken_general/20261112/stance/counter_upslash/motion/reverse_diagonal_upslash_520x350_20f.png'
    $animationArgument = '--counter-upslash'
}

if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Godot executable not found. Pass its path with -Godot.'
}
if (-not (Test-Path -LiteralPath $atlas -PathType Leaf)) {
    throw "Prototype atlas not found: $atlas"
}

$arguments = @(
    '--path', ('"{0}"' -f $game),
    '--rendering-method', 'gl_compatibility',
    '--resolution', '1280x720',
    '--script', ('"{0}"' -f $preview),
    '--', ('"{0}"' -f $atlas)
)
if ($animationArgument) {
    $arguments += $animationArgument
}
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Normal -PassThru
$process.WaitForExit()
exit $process.ExitCode
