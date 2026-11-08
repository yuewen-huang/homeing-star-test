param([string]$Godot = 'D:/Godot/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$previewProject = & (Join-Path $PSScriptRoot 'tools/prepare_title_opening.ps1') -Name 'opening-comic-preview'
$env:APPDATA = Join-Path $PSScriptRoot 'artifacts/opening-comic-preview/runtime'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$previewProcess = Start-Process -FilePath $Godot -ArgumentList @(
    '--path', ('"' + $previewProject + '"'),
    'res://scenes/story/comics/opening_comic.tscn'
) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $env:APPDATA 'preview.log') -RedirectStandardError (Join-Path $env:APPDATA 'preview.errors.log') -PassThru
$previewProcess.Id | Set-Content (Join-Path $env:APPDATA 'process.txt')
Write-Output "Opening comic preview: $($previewProcess.Id)"
