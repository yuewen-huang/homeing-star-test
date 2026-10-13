param([string]$Root = 'D:\homing-star-godot')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dir = Join-Path $Root 'assets/sideview/characters/lan/palette-trial'
[void][IO.Directory]::CreateDirectory($dir)
$src = [Drawing.Bitmap]::new((Join-Path $Root 'assets/sideview/characters/lan/idle.png'))
$concept = [Drawing.Bitmap]::new((Join-Path $Root 'assets/sideview/characters/lan/concepts/lan-short-robe-v8.png'))
# Sample real concept pixels nearest to specified material midtones.
$targets = @{
 hairLight='FFE7A5'; hair='F5D181'; hairShade='D7A35C'; hairDark='AB7745'
 fur='F4C477'; furShade='D99B50'; furDark='AB703C'
 cloth='315B60'; clothShade='27484C'; clothDark='20383D'; outline='192B30'
 cream='D9C49D'; creamShade='AE926C'; leather='79482F'; leatherLight='A36138'; leatherDark='482E26'
 eye='238678'; eyeDark='185A50'; glint='A7D7C6'
}
$samples=@{}; $best=@{}
foreach($name in $targets.Keys){$best[$name]=[double]::PositiveInfinity}
for($y=0;$y -lt $concept.Height;$y+=3){for($x=0;$x -lt $concept.Width;$x+=3){
 $c=$concept.GetPixel($x,$y)
 foreach($name in $targets.Keys){$t=[Drawing.ColorTranslator]::FromHtml('#'+$targets[$name]); $d=[math]::Pow(($c.R-$t.R),2)+[math]::Pow(($c.G-$t.G),2)+[math]::Pow(($c.B-$t.B),2); if($d -lt $best[$name]){$best[$name]=$d; $samples[$name]=$c}}
}}
$map=@{
 'FFFFFF'='hairLight'; 'FFFFCC'='hairLight'; 'B2B2FF'='hair'; '9EA0FA'='hairShade'; 'AD5FAD'='hairDark'
 '0321BC'='cloth'; '1C154D'='clothShade'; '40225F'='clothDark'; '2F1850'='clothDark'; '151037'='outline'
 'FF8C5E'='fur'; 'A96E67'='hairDark'; '882323'='leather'; '580303'='leatherDark'; '8C2309'='creamShade'
 'A64B0A'='creamShade'; 'FF0E00'='leatherLight'; 'E05E2B'='furShade'; '4D2F1E'='leatherDark'
 'FFA303'='cream'; '51373F'='leatherDark'; '431500'='furDark'; '007F26'='eye'; '006E22'='eyeDark'; '0F121B'='outline'; '97C0FF'='glint'
}
$original=[Drawing.Bitmap]::new(46,55); $output=[Drawing.Bitmap]::new(46,55)
$rows=[Collections.Generic.List[object]]::new(); $changed=0; $alphaErrors=0
for($y=0;$y -lt 55;$y++){for($x=0;$x -lt 46;$x++){
 $c=$src.GetPixel($x,$y); $original.SetPixel($x,$y,$c); $n=$c
 if($c.A -gt 0){
  $hex='{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B
  if(-not $map.ContainsKey($hex)){throw "Unmapped source $hex"}
  $material=$map[$hex]
  # Frame-one regional exceptions; these coordinates must not be blindly reused on other frames.
  if($hex -eq 'AD5FAD' -and $y -ge 39){$material='furShade'}
  if($hex -eq 'AD5FAD' -and $y -ge 35 -and $x -ge 33){$material='furShade'}
  if($hex -eq '882323' -and $y -lt 21){$material='furDark'}
  if($hex -eq '8C2309' -and $y -ge 39){$material='furDark'}
  $s=$samples[$material]; $n=[Drawing.Color]::FromArgb($c.A,$s.R,$s.G,$s.B)
  if($c.ToArgb() -ne $n.ToArgb()){$changed++}
  $rows.Add([pscustomobject]@{x=$x;y=$y;source=('#'+$hex);material=$material;target=('#{0:X2}{1:X2}{2:X2}' -f $s.R,$s.G,$s.B)})
 }
 $output.SetPixel($x,$y,$n)
 if($c.A -ne $n.A){$alphaErrors++}
}}
$original.Save((Join-Path $dir 'frame01-original.png'))
$output.Save((Join-Path $dir 'frame01-recolored.png'))
$rows | Export-Csv (Join-Path $dir 'frame01-pixel-map.csv') -NoTypeInformation -Encoding utf8
$rows | Group-Object source,material,target | ForEach-Object {$r=$_.Group[0]; [pscustomobject]@{source=$r.source;material=$r.material;target=$r.target;pixels=$_.Count}} | Export-Csv (Join-Path $dir 'frame01-color-map.csv') -NoTypeInformation -Encoding utf8
# Exact nearest-neighbor preview: left original, right recolored, 10x.
$preview=[Drawing.Bitmap]::new(980,590)
$g=[Drawing.Graphics]::FromImage($preview); $g.Clear([Drawing.Color]::FromArgb(65,65,69)); $g.Dispose()
for($side=0;$side -lt 2;$side++){$im=if($side -eq 0){$original}else{$output}; for($y=0;$y -lt 55;$y++){for($x=0;$x -lt 46;$x++){
 $c=$im.GetPixel($x,$y); if($c.A -eq 0){$v=if(($x/4 -as [int])%2 -eq ($y/4 -as [int])%2){100}else{115}; $c=[Drawing.Color]::FromArgb($v,$v,$v)}
 for($dy=0;$dy -lt 10;$dy++){for($dx=0;$dx -lt 10;$dx++){$preview.SetPixel(20+$side*480+$x*10+$dx,20+$y*10+$dy,$c)}}
}}}
$preview.Save((Join-Path $dir 'frame01-comparison-10x.png'))
if($alphaErrors -ne 0){throw 'Alpha validation failed'}
Write-Output "PASS: 46x55, alpha differences=$alphaErrors, changed RGB pixels=$changed; opaque audited pixels=$($rows.Count). Original sheet not written."
$preview.Dispose();$original.Dispose();$output.Dispose();$src.Dispose();$concept.Dispose()
