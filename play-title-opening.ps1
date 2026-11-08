param([string]$Godot = 'D:/Godot/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$previewProject = & (Join-Path $PSScriptRoot 'tools/prepare_title_opening.ps1') -Name 'title-opening-preview'
$env:APPDATA = Join-Path $PSScriptRoot 'artifacts/title-opening-preview/runtime'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
Start-Process -FilePath $Godot -ArgumentList @('--path', ('"' + $previewProject + '"')) -WindowStyle Hidden
