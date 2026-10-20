param([string]$Kind='deer',[int]$Phase=1,[switch]$Record)
$ErrorActionPreference='Stop'
$reelBase='D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps'
$reelOut=Join-Path $reelBase ($Kind+'_'+$Phase)
New-Item -ItemType Directory -Force $reelOut | Out-Null
$reelScript=if($Kind -eq 'master'){'D:/HomingStar/homeing-star-test/tools/record_boss_master_reel.gd'}elseif($Kind -eq 'crab'){'D:/HomingStar/homeing-star-test/tools/record_boss_crab_reel.gd'}else{'D:/HomingStar/homeing-star-test/tools/record_boss_reel.gd'}
function Run-Reel([string[]]$ReelArgs,[string]$Label,[int]$Limit){
 $reelProcess=Start-Process -FilePath 'D:/Godot/Godot_v4.7.2-stable_win64_console.exe' -Environment @{APPDATA=(Join-Path $reelBase 'profile')} -ArgumentList @($ReelArgs | ForEach-Object {'"'+$_+'"'}) -WindowStyle Hidden -RedirectStandardOutput "$reelOut/$Label.log" -RedirectStandardError "$reelOut/$Label.errors.log" -PassThru
 $null=$reelProcess.Handle
 $reelWatch=[Diagnostics.Stopwatch]::StartNew()
 try{
  while(-not $reelProcess.WaitForExit(500)){
   if((Select-String -LiteralPath "$reelOut/$Label.errors.log" -Pattern 'SCRIPT ERROR:|Parse Error:|Compilation failed' -Quiet) -or $reelWatch.Elapsed.TotalSeconds -gt $Limit){throw "Failed or timed out $Label"}
  }
  $reelProcess.WaitForExit()
  if($reelProcess.ExitCode -ne 0 -or (Select-String -LiteralPath "$reelOut/$Label.errors.log" -Pattern "SCRIPT ERROR:|Parse Error:|Compilation failed" -Quiet)){Get-Content "$reelOut/$Label.log" -Tail 12; Get-Content "$reelOut/$Label.errors.log"; throw "$Label failed"}
 }finally{if(-not $reelProcess.HasExited){$reelProcess.Kill()};$reelProcess.Dispose()}
}
Run-Reel @('--headless','--path','D:/HomingStar/homeing-star-test/artifacts/recording_project','--check-only','--script',$reelScript,'--log-file',"$reelOut/compile-engine.log") 'compile' 30
$reelArgs=@('--path','D:/HomingStar/homeing-star-test/artifacts/recording_project','--fixed-fps','60','--quit-after','8000','--script',$reelScript,'--log-file',"$reelOut/audit-engine.log",'--',$reelOut,$Kind,"$Phase")
if($Record){
 $reelArgs=@('--path','D:/HomingStar/homeing-star-test/artifacts/recording_project','--fixed-fps','60','--resolution','1280x720','--quit-after','8000','--write-movie',"$reelOut/raw.avi",'--script',$reelScript,'--log-file',"$reelOut/record-engine.log",'--',$reelOut,$Kind,"$Phase")
 Run-Reel $reelArgs 'record' 480
}else{
 Run-Reel (@('--headless')+$reelArgs) 'audit' 60
}
Get-Content "$reelOut/$(if($Record){'record'}else{'audit'}).log" -Tail 9
