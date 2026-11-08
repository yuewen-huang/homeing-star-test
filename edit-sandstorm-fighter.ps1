param([string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path "$PSScriptRoot/../smear-combo-demo").Path
& $Godot --path $project --rendering-method gl_compatibility res://pose_editor.tscn
