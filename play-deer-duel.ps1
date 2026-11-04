param([string]$Godot = 'E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe', [switch]$RootPhase)
$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\homeing-star-game')).Path
$script = Join-Path $PSScriptRoot 'tools\preview_deer_duel.gd'
$logDir = Join-Path $PSScriptRoot ('artifacts\deer-duel-play-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$arguments = @('--path', $game, '--rendering-method', 'gl_compatibility', '--script', $script, '--log-file', (Join-Path $logDir 'game.log'))
if ($RootPhase) { $arguments += @('--','--root-phase') }
$quoted = @($arguments | ForEach-Object { '"' + $_ + '"' })
$process = Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir 'stdout.log') -RedirectStandardError (Join-Path $logDir 'stderr.log')
$null = $process.Handle
Write-Host "DEER DUEL PID=$($process.Id); logs: $logDir"
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "Godot exited with code $($process.ExitCode); see $logDir" }
