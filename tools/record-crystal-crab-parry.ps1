[CmdletBinding()]
param(
  [string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe',
  [string]$Output = (Join-Path $PSScriptRoot '..\artifacts\crab-parry-weight')
)
$ErrorActionPreference = 'Stop'
$crabProject = (Resolve-Path (Join-Path $PSScriptRoot '..\..\homeing-star-game')).Path
$crabScript = Join-Path $PSScriptRoot 'record_crystal_crab_parry.gd'
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$Output = (Resolve-Path -LiteralPath $Output).Path

function Invoke-CrabEngine([string[]]$EngineArguments, [string]$Label, [int]$Limit) {
  $stdout = Join-Path $Output ($Label+'.log')
  $stderr = Join-Path $Output ($Label+'.errors.log')
  $quoted = @($EngineArguments | ForEach-Object { '"'+$_+'"' })
  $process = Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  $null = $process.Handle
  $clock = [Diagnostics.Stopwatch]::StartNew()
  try {
    while (-not $process.WaitForExit(500)) {
      if (Test-Path -LiteralPath $stderr) {
        if (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR:|Parse Error:|Compilation failed|Failed to load script' -Quiet) {
          throw "Godot script failed during $Label; see $stderr"
        }
      }
      if ($clock.Elapsed.TotalSeconds -gt $Limit) { throw "Godot $Label exceeded $Limit seconds" }
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR:|Parse Error:|Compilation failed|Failed to load script' -Quiet)) {
      throw "Godot $Label failed; see $stderr"
    }
  } finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
  }
}

# A compile failure must never start an unattended movie writer.
Invoke-CrabEngine @('--headless','--path',$crabProject,'--check-only','--script',$crabScript,'--log-file',(Join-Path $Output 'preflight-engine.log')) 'preflight' 20
Write-Host 'PASS recorder compilation; starting bounded recording.'
Invoke-CrabEngine @('--path',$crabProject,'--fixed-fps','60','--resolution','1280x720','--quit-after','2100','--write-movie',(Join-Path $Output 'crystal_crab_weight_parry.avi'),'--script',$crabScript,'--log-file',(Join-Path $Output 'record-engine.log'),'--',$Output) 'record' 90
if (-not (Select-String -LiteralPath (Join-Path $Output 'record.log') -Pattern 'CRAB PARRY RECORDING: PASS' -Quiet)) {
  throw 'Recording ended without completing the combat audit.'
}
Write-Host "PASS recorded and audited: $Output"
