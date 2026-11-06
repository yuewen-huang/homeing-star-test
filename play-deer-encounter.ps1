param([string]$Godot='E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe', [switch]$VinePhase)
$ErrorActionPreference='Stop'
$game=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../homeing-star-game')).Path
$script=Join-Path $PSScriptRoot 'tools/preview_deer_encounter.gd'
$logDir=Join-Path $PSScriptRoot ('artifacts/deer-encounter-play-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$arguments=@('--path',$game,'--rendering-method','gl_compatibility','--script',$script)
if ($VinePhase) { $arguments+=@('--','--vine-phase') }
$quoted=@($arguments | ForEach-Object {'"'+$_+'"'})
$process=Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $logDir 'stdout.log') -RedirectStandardError (Join-Path $logDir 'stderr.log')
$null=$process.Handle
Write-Host "DEER ENCOUNTER PID=$($process.Id); logs: $logDir"
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "Godot exited with code $($process.ExitCode); see $logDir" }
