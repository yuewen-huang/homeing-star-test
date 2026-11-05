param([switch]$Capture)
$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\homeing-star-game')).Path
$godot = 'E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$outputDir = Join-Path $PSScriptRoot ('artifacts\vine-growth-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$previousCapture = $env:HOMING_STAR_GROWTH_CAPTURE
$savePath = Join-Path $game 'save\progress.cfg'
$before = if (Test-Path -LiteralPath $savePath) { (Get-FileHash -LiteralPath $savePath).Hash } else { '' }
try {
    if ($Capture) { $env:HOMING_STAR_GROWTH_CAPTURE = $outputDir } else { $env:HOMING_STAR_GROWTH_CAPTURE = '' }
    $arguments = @('--path',$game,'--rendering-method','gl_compatibility','--fixed-fps','60','--script',(Join-Path $PSScriptRoot 'tools\preview_deer_vine_growth.gd'),'--log-file',(Join-Path $outputDir 'game.log'))
    $quoted = @($arguments | ForEach-Object { '"'+$_+'"' })
    $style = if ($Capture) { 'Hidden' } else { 'Normal' }
    $proc = Start-Process -FilePath $godot -ArgumentList $quoted -WindowStyle $style -PassThru -RedirectStandardOutput (Join-Path $outputDir 'stdout.log') -RedirectStandardError (Join-Path $outputDir 'stderr.log')
    $null = $proc.Handle
    Write-Host "ROOTED VINE PID=$($proc.Id); logs: $outputDir"
    if ($Capture) {
        if (-not $proc.WaitForExit(120000)) { $proc.Kill(); throw 'Growth capture timed out' }
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) { throw "Growth capture exited $($proc.ExitCode)" }
        $runtimeErrors = @(Get-Content -LiteralPath (Join-Path $outputDir 'stderr.log') | Where-Object {
            $_ -match '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)|Parse Error:' -and $_ -notmatch "^ERROR: Can't create shader cache folder"
        })
        if ($runtimeErrors.Count -gt 0) { throw ('Growth capture had runtime errors: '+($runtimeErrors -join ' / ')) }
        $after = if (Test-Path -LiteralPath $savePath) { (Get-FileHash -LiteralPath $savePath).Hash } else { '' }
        if ($before -ne $after) { throw 'Unexpected save mutation' }
        Write-Host 'Growth capture complete; save unchanged.'
    } else { $proc.WaitForExit() }
} finally { $env:HOMING_STAR_GROWTH_CAPTURE = $previousCapture }
