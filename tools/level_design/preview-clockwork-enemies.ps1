param(
    [ValidateSet('Ox', 'Bird', 'Snake')]
    [string]$Enemy = 'Ox',
    [string]$Godot = 'E:/Godot Hub/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Godot executable not found. Pass its path with -Godot.'
}
$testRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gameRoot = (Resolve-Path -LiteralPath (Join-Path $testRoot '../homeing-star-game')).Path
$preview = Join-Path $PSScriptRoot 'preview_clockwork_enemies.gd'
$launchArguments = @(
    '--path', ('"{0}"' -f $gameRoot),
    '--rendering-method', 'gl_compatibility',
    '--resolution', '1280x720',
    '--script', ('"{0}"' -f $preview),
    '--', ('--' + $Enemy.ToLowerInvariant())
)
$gameProcess = Start-Process -FilePath $Godot -ArgumentList $launchArguments -WindowStyle Normal -PassThru
$gameProcess.WaitForExit()
exit $gameProcess.ExitCode
