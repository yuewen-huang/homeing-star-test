[CmdletBinding()]
param([string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$towerProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../homeing-star-game')).Path
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Godot executable not found; specify -Godot.' }
$towerLog = Join-Path $PSScriptRoot '../../artifacts/underwater_tower_foundation/preview-engine.log'
$towerLog = [IO.Path]::GetFullPath($towerLog)
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($towerLog)) | Out-Null
Start-Process -FilePath $Godot -WindowStyle Hidden -ArgumentList @('--path', ('"'+$towerProject+'"'), '--log-file', ('"'+$towerLog+'"'), 'res://scenes/levels/chapter_2_underwater/tower/underwater_tower_foundation.tscn')
