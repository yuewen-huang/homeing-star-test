$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$taskOut = 'D:\HomingStar\homeing-star-temp-assert\Recordings\20261019_boss_real_maps\progress_share_release'
$cueList = Get-Content -LiteralPath (Join-Path $taskOut 'voice_text.json') -Raw -Encoding utf8 | ConvertFrom-Json
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speaker.SelectVoice('Microsoft Huihui Desktop')
$speaker.Rate = 2
$speaker.Volume = 100
$index = 0
foreach ($cue in $cueList) {
    $target = Join-Path $taskOut ('voice_{0:d2}.wav' -f $index)
    if (!(Test-Path -LiteralPath $target)) {
        $speaker.SetOutputToWaveFile($target)
        $spoken = $cue.Replace('BOSS', 'Boss').Replace('《', '').Replace('》', '').Replace('Steam', '斯蒂姆')
        $speaker.Speak($spoken)
        $speaker.SetOutputToNull()
    }
    Write-Output ('VOICE {0:d2}: {1}' -f $index, $cue)
    $index += 1
}
$speaker.Dispose()
