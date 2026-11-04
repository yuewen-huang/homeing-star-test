param(
  [string]$Godot = 'E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\homeing-star-game')).Path
$script = Join-Path $PSScriptRoot 'tools\preview_deer_training.gd'
$logDir = Join-Path $PSScriptRoot 'artifacts\deer-training-play'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$argsList = @('--path', $game, '--rendering-method', 'gl_compatibility', '--script', $script, '--log-file', (Join-Path $logDir 'game.log'))
$quoted = @($argsList | ForEach-Object { '"' + $_ + '"' })
# Hide only the console; Godot opens the native game window for the user's playtest.
$process = Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir 'stdout.log') -RedirectStandardError (Join-Path $logDir 'stderr.log')
$null = $process.Handle
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "Godot exited with code $($process.ExitCode); see $logDir" }
