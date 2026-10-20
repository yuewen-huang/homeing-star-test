[CmdletBinding()]
param(
  [string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe',
  [string]$Output = (Join-Path $PSScriptRoot '..\artifacts\录屏\master-scripted-v1'),
  [switch]$ValidateOnly,
  [switch]$Duel
)
$ErrorActionPreference = 'Stop'
$masterProject = (Resolve-Path (Join-Path $PSScriptRoot '..\..\homeing-star-game')).Path
$masterScript = Join-Path $PSScriptRoot $(if ($Duel) {'record_master_duel.gd'} else {'record_master_showcase.gd'})
$masterFrames = if ($Duel) {'12000'} else {'5000'}
$masterAudit = if ($Duel) {'MASTER DUEL: 11 checks, 0 failures'} else {'MASTER SHOWCASE: 12 checks, 0 failures'}
$masterMovie = if ($Duel) {'master_duel.avi'} else {'master_showcase.avi'}
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$Output = (Resolve-Path -LiteralPath $Output).Path

function Invoke-MasterRecorder([string[]]$EngineArguments, [string]$Label, [int]$Limit) {
  $stdout = Join-Path $Output ($Label+'.log')
  $stderr = Join-Path $Output ($Label+'.errors.log')
  $quoted = @($EngineArguments | ForEach-Object { '"'+$_+'"' })
  $process = Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  $null = $process.Handle
  $clock = [Diagnostics.Stopwatch]::StartNew()
  try {
    while (-not $process.WaitForExit(500)) {
      if ((Test-Path -LiteralPath $stderr) -and (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR:|SHADER ERROR:|Parse Error:|Compilation failed|Shader compilation failed' -Quiet)) {
        throw "Script error in $Label; see $stderr"
      }
      if ($clock.Elapsed.TotalSeconds -gt $Limit) { throw "$Label exceeded $Limit seconds" }
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "$Label failed; see $stdout and $stderr" }
  } finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
  }
}

Invoke-MasterRecorder @('--headless','--path',$masterProject,'--check-only','--script',$masterScript,'--log-file',(Join-Path $Output 'preflight-engine.log')) 'preflight' 25
Invoke-MasterRecorder @('--headless','--path',$masterProject,'--fixed-fps','60','--quit-after',$masterFrames,'--script',$masterScript,'--log-file',(Join-Path $Output 'audit-engine.log'),'--',$Output) 'audit' 40
if (-not (Select-String -LiteralPath (Join-Path $Output 'audit.log') -Pattern $masterAudit -Quiet)) { throw 'Combat audit did not complete' }
Write-Host 'PASS production-combat input audit.'
if ($ValidateOnly) { exit 0 }
Invoke-MasterRecorder @('--path',$masterProject,'--fixed-fps','60','--resolution','1280x720','--quit-after',$masterFrames,'--write-movie',(Join-Path $Output $masterMovie),'--script',$masterScript,'--log-file',(Join-Path $Output 'record-engine.log'),'--',$Output) 'record' 360
if (-not (Select-String -LiteralPath (Join-Path $Output 'record.log') -Pattern $masterAudit -Quiet)) { throw 'Recording did not complete the combat audit' }
Write-Host "PASS recorded: $Output"
