[CmdletBinding()]
param([string]$Godot='D:\Godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference='Stop'
$projectPath=(Resolve-Path (Join-Path $PSScriptRoot '..\homeing-star-game')).Path
$runPath=Join-Path $PSScriptRoot ('artifacts\salt-bake-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $runPath | Out-Null
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Godot executable not found; specify -Godot.' }
function Invoke-BakeStep([string[]]$EngineArguments,[string]$Label) {
  $quoted=@($EngineArguments | ForEach-Object {'"'+$_+'"'})
  $outputPath=Join-Path $runPath ($Label+'.log')
  $errorPath=Join-Path $runPath ($Label+'.errors.log')
  $process=Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
  $null=$process.Handle
  if (-not $process.WaitForExit(120000)) { $process.Kill(); throw "$Label timed out." }
  $process.WaitForExit()
  if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $errorPath -Pattern 'SCRIPT ERROR:|Parse Error:' -Quiet)) {
    Get-Content -LiteralPath $errorPath -Tail 15
    throw "$Label failed; see $runPath"
  }
}
Invoke-BakeStep @('--path',$projectPath,'--script',(Join-Path $PSScriptRoot 'tools\art\bake_salt_boundary_pages.gd'),'--log-file',(Join-Path $runPath 'engine.log')) 'bake'
Invoke-BakeStep @('--headless','--path',$projectPath,'--editor','--import','--quit') 'import'
Get-Content -LiteralPath (Join-Path $runPath 'bake.log') | Select-String 'BOUNDARY BAKE'
Write-Host "Salt boundary bake ready. Logs: $runPath"
