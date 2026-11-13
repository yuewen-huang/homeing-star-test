param(
    [string]$Godot,
    [switch]$Toad,
    [switch]$StakeChain,
    [switch]$WestShafts,
    [switch]$WestShaftReturn,
    [switch]$HiddenDoor,
    [switch]$HiddenLayout,
    [switch]$HiddenGateArt
)
$ErrorActionPreference = 'Stop'
if (-not $Godot) {
    $Godot = @(
        'D:/Godot/Godot_v4.7.2-stable_win64.exe'
        'E:/Godot Hub/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Godot executable not found. Pass its path with -Godot.'
}
$cavernWorkspace = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$cavernGame = Join-Path $cavernWorkspace 'homeing-star-game'
$cavernScript = Join-Path $PSScriptRoot $(if ($HiddenLayout -and -not $HiddenGateArt) { 'preview_zhenxi_layout.gd' } else { 'preview_sunken_cavern.gd' })
$cavernArtifacts = Join-Path $cavernWorkspace 'homeing-star-test/artifacts/sunken_cavern_graybox_20261101'
New-Item -ItemType Directory -Path $cavernArtifacts -Force | Out-Null
$cavernLog = Join-Path $cavernArtifacts ('preview-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$cavernArgs = @('--path', ('"{0}"' -f $cavernGame), '--rendering-method', 'gl_compatibility', '--log-file', ('"{0}"' -f $cavernLog), '--position', '80,80', '--resolution', '1280x720', '--script', ('"{0}"' -f $cavernScript))
if ($HiddenGateArt) { $cavernArgs += @('--', '--gate-art') }
elseif ($HiddenDoor) { $cavernArgs += @('--', '--hidden-door') }
elseif ($WestShaftReturn) { $cavernArgs += @('--', '--west-shaft-return') }
elseif ($WestShafts) { $cavernArgs += @('--', '--west-shafts') }
elseif ($Toad -or $StakeChain) {
    $cavernArgs += @('--', '--toad')
    if ($StakeChain) { $cavernArgs += '--stake-chain' }
}
$cavernProcess = Start-Process -FilePath $Godot -ArgumentList $cavernArgs -WindowStyle Normal -PassThru
Write-Output ('Sunken cavern preview PID: ' + $cavernProcess.Id)
$cavernProcess.WaitForExit()
exit $cavernProcess.ExitCode
