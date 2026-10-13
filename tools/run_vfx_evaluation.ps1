param([switch]$Still, [string[]]$Cases = @('smoke_raw','smoke_adapted','wave_baseline','fog_raw','fog_baseline','rope_raw','rope_adapted','rope_stress','grass'))

$ErrorActionPreference = 'Stop'
$engine = 'E:\Godot Hub\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$project = (Join-Path $PSScriptRoot '..\vfx-evaluation')
$logs = (Join-Path $PSScriptRoot '..\artifacts\deer-mist-20261010')

foreach ($case in $Cases) {
    $arguments = @('--path', $project, '--fixed-fps', '60', '--audio-driver', 'Dummy', '--log-file', "$logs\eval-$case-engine.log", '--', '--case', $case)
    if ($Still) { $arguments += '--still' }
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$logs\eval-$case.log" -RedirectStandardError "$logs\eval-$case-errors.log"
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "Timed out: $case"
    }
    $exitCode = $process.ExitCode
    $errors = Get-Content -LiteralPath "$logs\eval-$case-errors.log" -Raw
    if ($errors -match 'SCRIPT ERROR|Parse Error|Shader compilation failed|Invalid') {
        Write-Output $errors
        throw "Runtime error: $case"
    }
    Get-Content -LiteralPath "$logs\eval-$case.log" -Tail 1
    if ($exitCode -ne 0) { throw "Exit code $exitCode for $case" }
}
