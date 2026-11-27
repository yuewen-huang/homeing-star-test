<#
.SYNOPSIS
Replays the Mist Forest canopy route from the entrance to the deer gate.
.EXAMPLE
pwsh -File tools/level_design/replay-mist-forest-canopy.ps1
.EXAMPLE
pwsh -File tools/level_design/replay-mist-forest-canopy.ps1 -Movie
.NOTES
Each run writes an input trace and Godot logs under artifacts/. Movie mode also
writes an AVI at 1280×720 and 60 FPS. Probe mode starts in a selected chamber.
#>
[CmdletBinding()]
param(
    [string]$Project = (Join-Path $PSScriptRoot '../../../homeing-star-game'),
    [string]$Godot = 'E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [ValidateRange(0, 5)][int]$Probe = 0,
    [ValidateRange(1, 2147483617)][int]$Frames = 9350,
    [switch]$Movie
)

$ErrorActionPreference = 'Stop'
$Project = (Resolve-Path -LiteralPath $Project).Path
if (-not (Test-Path -LiteralPath (Join-Path $Project 'project.godot'))) {
    throw 'Project must contain project.godot.'
}
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Godot executable not found. Specify -Godot with its Windows console executable path.'
}
$testRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $testRoot ('artifacts/mist-forest-canopy-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$isolatedUser = New-Item -ItemType Directory -Path (Join-Path $output 'user') -Force
$scriptPath = Join-Path $PSScriptRoot 'replay_mist_forest_canopy.gd'
$log = Join-Path $output 'godot.log'
$stdout = Join-Path $output 'replay.log'
$stderr = Join-Path $output 'replay.errors.log'
$arguments = @('--path', $Project, '--fixed-fps', '60', '--max-fps', '0', '--log-file', $log)
if ($Movie) {
    $arguments += @('--resolution', '1280x720', '--disable-vsync', '--write-movie', (Join-Path $output 'replay.avi'))
} else {
    $arguments += @('--headless', '--disable-render-loop')
}
$arguments += @('--quit-after', ($Frames + 30), '--script', $scriptPath, '--', $Probe, $Frames)
$quotedArguments = @($arguments | ForEach-Object { '"' + $_ + '"' })
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousOutput = $env:HOMING_STAR_TEST_OUTPUT
try {
    $env:APPDATA = $isolatedUser.FullName
    $env:LOCALAPPDATA = $isolatedUser.FullName
    $env:HOMING_STAR_TEST_OUTPUT = $output
    Write-Host "Replay output: $output"
    $process = Start-Process -FilePath $Godot -ArgumentList $quotedArguments -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $null = $process.Handle
    $process.WaitForExit()
    Get-Content -LiteralPath $stdout -Tail 18
    if ($process.ExitCode -ne 0) {
        Get-Content -LiteralPath $stderr -Tail 18
    }
    exit $process.ExitCode
} finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:HOMING_STAR_TEST_OUTPUT = $previousOutput
}
