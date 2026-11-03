param(
    [string]$Godot = 'D:/Godot/Godot_v4.7.2-stable_win64.exe',
    [switch]$Combat,
    [switch]$Chop,
    [switch]$Wind,
    [switch]$Triple,
    [switch]$Phase2
)
$ErrorActionPreference = 'Stop'
$flowWorkspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$flowGame = Join-Path $flowWorkspace 'homeing-star-game'
$flowScript = Join-Path $PSScriptRoot 'preview_master_flow.gd'
$flowArtifacts = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/master-flow'
New-Item -ItemType Directory -Path $flowArtifacts -Force | Out-Null
$flowLog = Join-Path $flowArtifacts ('preview-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$flowArgs = @('--path', ('"{0}"' -f $flowGame), '--log-file', ('"{0}"' -f $flowLog), '--position', '80,80', '--resolution', '1280x720', '--script', ('"{0}"' -f $flowScript))
if ($Combat -or $Chop -or $Wind -or $Triple -or $Phase2) { $flowArgs += '--' }
if ($Phase2) { $flowArgs += '--phase2' }
if ($Combat) { $flowArgs += '--combat' }
if ($Chop -or $Wind -or $Triple) { $flowArgs += '--chop' }
if ($Wind) { $flowArgs += '--wind' }
if ($Triple) { $flowArgs += '--triple' }
$flowProcess = Start-Process -FilePath $Godot -ArgumentList $flowArgs -WindowStyle Normal -PassThru
Write-Output ('Master flow preview PID: ' + $flowProcess.Id)
Write-Output ('Log: ' + $flowLog)
