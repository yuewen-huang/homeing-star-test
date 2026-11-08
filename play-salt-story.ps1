param([string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../homeing-star-game')).Path
$review = Join-Path $PSScriptRoot 'tools/salt_story_review.gd'
$env:APPDATA = Join-Path $PSScriptRoot 'artifacts/salt-story-review-runtime'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
Start-Process -FilePath $Godot -ArgumentList @('--path',('"'+$project+'"'),'--script',('"'+$review+'"')) -WindowStyle Hidden
