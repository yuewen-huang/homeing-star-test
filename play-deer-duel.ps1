param([string]$Godot = 'E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe', [switch]$RootPhase, [switch]$VinePhase, [switch]$RushRedraw, [switch]$VineGround, [switch]$VineHunt, [switch]$PlowUppercut, [switch]$VinePursuit, [switch]$WindPhase)
$ErrorActionPreference = 'Stop'
if ($VineGround -or $VineHunt -or $PlowUppercut -or $VinePursuit) { $VinePhase = $true }
if ($WindPhase -and ($RootPhase -or $VinePhase -or $RushRedraw)) { throw 'Select only one phase' }
if ($VinePursuit -and ($VineGround -or $VineHunt -or $PlowUppercut)) { throw 'Pursuit combat uses its own repertoire' }
if ($PlowUppercut -and ($VineGround -or $VineHunt)) { throw 'Source preview cannot select a combat exercise' }
if ($VineGround -and $VineHunt) { throw 'Select only one vine exercise' }
$game = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\homeing-star-game')).Path
$script = Join-Path $PSScriptRoot 'tools\preview_deer_duel.gd'
$logDir = Join-Path $PSScriptRoot ('artifacts\deer-duel-play-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$arguments = @('--path', $game, '--rendering-method', 'gl_compatibility', '--script', $script, '--log-file', (Join-Path $logDir 'game.log'))
if ($RootPhase -and $VinePhase) { throw 'Select only one phase' }
if ($RushRedraw -and ($RootPhase -or $VinePhase)) { throw 'RushRedraw uses the first-phase room' }
if ($RootPhase) { $arguments += @('--','--root-phase') }
if ($WindPhase) { $arguments += @('--','--wind-phase') }
if ($VinePhase) { $arguments += @('--','--vine-phase') }
if ($VineGround) { $arguments += '--vine-ground' }
if ($VineHunt) { $arguments += '--vine-hunt' }
if ($VinePursuit) { $arguments += '--vine-pursuit' }
if ($PlowUppercut) { $arguments += '--plow-uppercut' }
if ($RushRedraw) { $arguments += @('--','--rush-redraw') }
$quoted = @($arguments | ForEach-Object { '"' + $_ + '"' })
$process = Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $logDir 'stdout.log') -RedirectStandardError (Join-Path $logDir 'stderr.log')
$null = $process.Handle
Write-Host "DEER DUEL PID=$($process.Id); logs: $logDir"
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "Godot exited with code $($process.ExitCode); see $logDir" }
