param([string]$Name = 'title-opening')
$ErrorActionPreference = 'Stop'
if ($Name -notmatch '^[a-z0-9-]+$') { throw 'Invalid isolated project name' }
$gamePath = (Resolve-Path (Join-Path $PSScriptRoot '../../homeing-star-game')).Path
$sandboxPath = Join-Path $PSScriptRoot "../artifacts/$Name/project"
New-Item -ItemType Directory -Force $sandboxPath | Out-Null
$sandboxPath = (Resolve-Path $sandboxPath).Path
foreach ($folder in @('assets','scenes','scripts','.godot')) {
    $linkPath = Join-Path $sandboxPath $folder
    if (-not (Test-Path -LiteralPath $linkPath)) {
        New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $gamePath $folder) | Out-Null
    }
}
foreach ($file in @('project.godot','default_bus_layout.tres','icon.svg')) {
    if (Test-Path (Join-Path $gamePath $file)) {
        Copy-Item -LiteralPath (Join-Path $gamePath $file) -Destination (Join-Path $sandboxPath $file) -Force
    }
}
# Deliberately no link to the real save directory. All story writes stay here.
Write-Output $sandboxPath
