[CmdletBinding()]
param(
  [string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe',
  [switch]$Production,
  [switch]$Capture
)
$ErrorActionPreference = 'Stop'
$taskGame = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\homeing-star-game')).Path
$taskScript = Join-Path $PSScriptRoot 'preview_deer_lash_tiled.gd'
$taskOutput = Join-Path $PSScriptRoot ('..\artifacts\lash-tiled-' + $(if ($Production) {'production'} else {'development'}))
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskArgs = @('--path',$taskGame,'--fixed-fps','60','--script',$taskScript,'--log-file',(Join-Path $taskOutput 'engine.log'),'--',$taskOutput)
if ($Production) { $taskArgs += '--production' }
if (-not $Capture) { $taskArgs += '--live' }
& $Godot @taskArgs
exit $LASTEXITCODE
