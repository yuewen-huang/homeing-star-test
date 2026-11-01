param(
    [string]$Godot = 'D:/Godot/Godot_v4.7.2-stable_win64.exe'
)
$ErrorActionPreference = 'Stop'
$cavernWorkspace = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$cavernGame = Join-Path $cavernWorkspace 'homeing-star-game'
$cavernScript = Join-Path $PSScriptRoot 'preview_sunken_cavern.gd'
$cavernArtifacts = Join-Path $cavernWorkspace 'homeing-star-test/artifacts/sunken_cavern_graybox_20261101'
New-Item -ItemType Directory -Path $cavernArtifacts -Force | Out-Null
$cavernLog = Join-Path $cavernArtifacts ('preview-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$cavernArgs = @('--path', ('"{0}"' -f $cavernGame), '--log-file', ('"{0}"' -f $cavernLog), '--position', '80,80', '--resolution', '1280x720', '--script', ('"{0}"' -f $cavernScript))
$cavernProcess = Start-Process -FilePath $Godot -ArgumentList $cavernArgs -WindowStyle Normal -PassThru
Write-Output ('Sunken cavern preview PID: ' + $cavernProcess.Id)
$cavernProcess.WaitForExit()
exit $cavernProcess.ExitCode
