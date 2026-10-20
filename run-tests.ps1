[CmdletBinding()]
param(
  [string]$Project = (Join-Path $PSScriptRoot '..\homeing-star-game'),
  [string]$Godot = 'E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
  [string[]]$Test,
  [switch]$All,
  [switch]$List,
  [switch]$Prepare,
  [switch]$CheckOnly,
  [switch]$Visual,
  [int]$TimeoutSeconds = 120,
  [string[]]$TestArguments = @()
)
$ErrorActionPreference = 'Stop'
$Project = (Resolve-Path -LiteralPath $Project).Path
$available = @(Get-ChildItem (Join-Path $PSScriptRoot 'tools'), (Join-Path $PSScriptRoot 'tests') -Recurse -Filter 'test_*.gd' | Sort-Object FullName)
if ($List) { $available | ForEach-Object { $_.FullName.Substring($PSScriptRoot.Length+1) }; exit 0 }
if (-not (Test-Path -LiteralPath (Join-Path $Project 'project.godot'))) { throw 'Project must contain project.godot' }
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Godot executable not found; specify -Godot' }
if ($All) { $selected = $available }
elseif ($Test) {
  $selected = @($Test | ForEach-Object {
    $name = [IO.Path]::GetFileNameWithoutExtension($_)
    $match = @($available | Where-Object { $_.BaseName -eq $name })
    if ($match.Count -ne 1) { throw "Unknown or ambiguous test: $_" }
    $match[0]
  })
} else {
  $names = @('test_wind_flight_model','test_vine_flight_model','test_rune_lock','test_mist_parry_remake','test_chapter_1_boss_rooms')
  $selected = @($available | Where-Object { $_.BaseName -in $names })
}
$runDir = Join-Path $PSScriptRoot ('artifacts\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$saveFile = Join-Path $Project 'save\progress.cfg'
$hadSave = Test-Path -LiteralPath $saveFile
if ($hadSave) { $saveBytes = [IO.File]::ReadAllBytes($saveFile); [IO.File]::WriteAllBytes((Join-Path $runDir 'progress.cfg.backup'),$saveBytes) }
$oldOutput = $env:HOMING_STAR_TEST_OUTPUT
$env:HOMING_STAR_TEST_OUTPUT = $runDir
$failures = 0
function Invoke-Engine([string[]]$Arguments, [string]$Label) {
  $stdout = Join-Path $runDir ($Label+'.log')
  $stderr = Join-Path $runDir ($Label+'.errors.log')
  $quoted = @($Arguments | ForEach-Object { '"'+$_+'"' })
  $proc = Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  $null = $proc.Handle  # Windows PowerShell 5.1 reports a null ExitCode unless the handle is cached before exit.
  if (-not $proc.WaitForExit($TimeoutSeconds*1000)) {
    $proc.Kill(); $proc.WaitForExit()
    Write-Host "TIMEOUT $Label"
    return $false
  }
  $proc.WaitForExit()
  $badLog = Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR:|SHADER ERROR:|Parse Error:|Shader compilation failed' -Quiet
  $ok = $proc.ExitCode -eq 0 -and -not $badLog
  Write-Host ($(if ($ok) {'PASS'} else {'FAIL'})+' '+$Label)
  if (-not $ok) { Get-Content -LiteralPath $stderr -Tail 15 | ForEach-Object { Write-Host $_ }; Get-Content -LiteralPath $stdout -Tail 8 | ForEach-Object { Write-Host $_ } }
  return $ok
}
try {
  if ($Prepare) {
    if (-not (Invoke-Engine @('--headless','--path',$Project,'--editor','--import','--quit') 'import')) { throw 'Godot import failed' }
  }
  foreach ($item in $selected) {
    $arguments = @('--path',$Project,'--fixed-fps','60','--script',$item.FullName)
    if (-not $Visual -or $CheckOnly) { $arguments = @('--headless')+$arguments }
    if ($CheckOnly) { $arguments += '--check-only' }
    if ($TestArguments.Count) { $arguments += @('--')+$TestArguments }
    if (-not (Invoke-Engine $arguments $item.BaseName)) { $failures++ }
  }
} finally {
  if ($hadSave) { [IO.File]::WriteAllBytes($saveFile,$saveBytes) }
  elseif (Test-Path -LiteralPath $saveFile) { Remove-Item -LiteralPath $saveFile }
  $env:HOMING_STAR_TEST_OUTPUT = $oldOutput
}
Write-Host "Tests: $($selected.Count), failures: $failures; logs: $runDir"
exit $(if ($failures) {1} else {0})
