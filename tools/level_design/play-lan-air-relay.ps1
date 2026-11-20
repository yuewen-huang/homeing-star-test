[CmdletBinding()]
param(
    [string]$Godot = 'E:/Godot Hub/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot '../../../homeing-star-game'
$room = Join-Path $PSScriptRoot 'lan_air_relay.gd'
$log = Join-Path $PSScriptRoot 'play.log'
& $Godot --path $project --rendering-method gl_compatibility --resolution 1280x720 --log-file $log --script $room
exit $LASTEXITCODE
