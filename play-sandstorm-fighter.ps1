param([string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe', [ValidateSet(1,2,3,4)][int]$Skill = 1)
$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\homeing-star-game')).Path
$logs = Join-Path $PSScriptRoot ('artifacts\sandstorm-fighter-play-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$arguments = @('--path', $game, '--rendering-method', 'gl_compatibility', '--log-file', (Join-Path $logs 'game.log'), 'res://scenes/dev/sandstorm_fighter_room.tscn')
if ($Skill -eq 2) { $arguments += @('--', '--thomas') }
if ($Skill -eq 3) { $arguments += @('--', '--ambush') }
if ($Skill -eq 4) { $arguments += @('--', '--ai') }
$quoted = @($arguments | ForEach-Object { '"' + $_ + '"' })
$process = Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $logs 'stdout.log') -RedirectStandardError (Join-Path $logs 'stderr.log')
Write-Host "蝎女开发房 PID=$($process.Id); logs: $logs"
