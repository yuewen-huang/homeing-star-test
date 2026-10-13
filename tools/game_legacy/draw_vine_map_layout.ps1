Add-Type -AssemblyName System.Drawing
$outDir = Join-Path $PSScriptRoot '../docs/design/chapter_1_vine'
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null
$bitmap = [System.Drawing.Bitmap]::new(1600, 1100)
$g = [System.Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.ColorTranslator]::FromHtml('#111d25'))
$svg = [System.Text.StringBuilder]::new()
[void]$svg.AppendLine('<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1100" viewBox="0 0 1600 1100"><rect width="1600" height="1100" fill="#111d25"/>')
function Box($x,$y,$w,$h,$fill,$stroke='',$sw=1) {
  $b=[System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($fill))
  $g.FillRectangle($b,[single]$x,[single]$y,[single]$w,[single]$h); $b.Dispose()
  if($stroke){$p=[System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml($stroke),$sw);$g.DrawRectangle($p,[single]$x,[single]$y,[single]$w,[single]$h);$p.Dispose()}
  [void]$svg.AppendLine("<rect x='$x' y='$y' width='$w' height='$h' fill='$fill' stroke='$(if($stroke){$stroke}else{'none'})' stroke-width='$sw'/>")
}
function Line($x1,$y1,$x2,$y2,$color,$width=2,$dash=$false) {
  $p=[System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml($color),$width)
  if($dash){$p.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dash}
  $g.DrawLine($p,[single]$x1,[single]$y1,[single]$x2,[single]$y2);$p.Dispose()
  [void]$svg.AppendLine("<line x1='$x1' y1='$y1' x2='$x2' y2='$y2' stroke='$color' stroke-width='$width' $(if($dash){'stroke-dasharray="7 6"'})/>")
}
function Text($x,$y,$text,$size=18,$color='#dbe8ed') {
  $font=[System.Drawing.Font]::new('Microsoft YaHei',$size,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel)
  $brush=[System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($color))
  $g.DrawString($text,$font,$brush,[single]$x,[single]$y);$font.Dispose();$brush.Dispose()
  $escaped=[System.Security.SecurityElement]::Escape($text)
  [void]$svg.AppendLine("<text x='$x' y='$($y+$size)' font-family='Microsoft YaHei, sans-serif' font-size='$size' fill='$color'>$escaped</text>")
}
function Platform($x,$y,$w,$safe=$false) {
  if($safe){$base='#556d70';$edge='#99d4be'}else{$base='#86634b';$edge='#c4ae69'}
  Box $x $y $w 16 $base '#233c39' 2
  Line $x $y ($x+$w) $y $edge 4
  if(!$safe){
    for($i=18;$i -lt $w-8;$i+=35){Line ($x+$i) ($y+3) ($x+$i-5) ($y+8) '#302d27' 2;Line ($x+$i-5) ($y+8) ($x+$i-2) ($y+16) '#302d27' 2}
    Line ($x+4) ($y+22) ($x+$w-4) ($y+22) '#e1bb62' 2 $true
  } else {Box ($x+5) ($y+16) ($w-10) 8 '#344c4b'}
}
function Vine($x,$y,$length) {
  # A wooden ceiling mount and a visible hanging vine body; no target knot.
  Line ($x-17) $y ($x+18) $y '#8e7960' 5
  $lastX=$x;$lastY=$y
  for($i=8;$i -le $length;$i+=8){
    $xx=$x+4*[math]::Sin($i/27.0)
    Line $lastX $lastY $xx ($y+$i) '#81b878' 4
    if($i%32 -eq 0){Line $xx ($y+$i) ($xx+10) ($y+$i-7) '#9cca7e' 3}
    $lastX=$xx;$lastY=$y+$i
  }
}
function Arrow($x1,$y1,$x2,$y2,$color='#76c7e4',$dash=$false) {
  Line $x1 $y1 $x2 $y2 $color 3 $dash
  $angle=[math]::Atan2($y2-$y1,$x2-$x1)
  foreach($off in @(-0.55,0.55)){Line $x2 $y2 ($x2-12*[math]::Cos($angle+$off)) ($y2-12*[math]::Sin($angle+$off)) $color 3}
}
function Zone($x,$y,$w,$h,$color,$title) {
  Box $x $y $w $h '#172a30' $color 2
  Text ($x+10) ($y+8) $title 21 $color
}

Text 20 12 '藤区 · 简易地图设计 v1' 30 '#e5eee8'
Text 21 52 '4 × 3 屏 / 5120 × 2160     预挂藤蔓摆荡 · 普通地块踩后延迟坍塌' 18 '#97b7bd'
$xs=@(20,415,810,1205);$ys=@(92,374,656)
$titles=@('高处休息 / 转向','上层连续摆荡','错层换藤','上层终点', '左侧向上换藤','战斗区域','回摆与落点','右侧上升', '入口 / 单藤起步','普通解谜空间','连续换藤','根区出口 / 转向')
for($r=0;$r -lt 3;$r++) {for($c=0;$c -lt 4;$c++){
  $x=$xs[$c];$y=$ys[$r];$n=$r*4+$c+1;$letter=@('C','B','A')[$r]
  Box $x $y 375 266 '#142129' '#647d88' 1.5
  for($gx=$x+24;$gx -lt $x+375;$gx+=24){Line $gx $y $gx ($y+266) '#1b2b33' 1}
  for($gy=$y+24;$gy -lt $y+266;$gy+=24){Line $x $gy ($x+375) $gy '#1b2b33' 1}
  Text ($x+12) ($y+9) "$n   $letter$($c+1)" 23
  Text ($x+12) ($y+42) $titles[$n-1] 15 '#8aa5ae'
}}

# C1: permanent rest, then three pre-hung vines towards C2.
Platform 37 290 100 $true; Platform 292 252 86
Vine 160 175 280;Vine 230 134 110;Vine 315 155 66
Arrow 117 279 157 242 '#76c7e4' $true;Arrow 176 249 236 216 '#76c7e4' $true;Arrow 257 226 305 238 '#76c7e4' $true
Text 48 308 '休息台' 14 '#99d4be'
# C2: alternating drops and catches.
Platform 433 251 70;Platform 581 298 60;Platform 698 227 72
Vine 507 147 99;Vine 609 159 101;Vine 710 142 65
Arrow 494 239 550 231 '#76c7e4' $true;Arrow 561 245 607 272 '#76c7e4' $true;Arrow 634 273 710 215 '#76c7e4' $true
# C3: enough open air for long swing, two failure catches.
Platform 828 229 63;Platform 936 301 65;Platform 1093 246 72
Vine 905 147 94;Vine 1029 132 116;Vine 1142 146 73
Arrow 880 217 941 235 '#76c7e4' $true;Arrow 967 256 1043 215 '#76c7e4' $true;Arrow 1060 224 1120 231 '#76c7e4' $true
# C4 terminal stable foothold, no invented boss portal.
Platform 1223 246 68;Platform 1467 274 89 $true
Vine 1315 154 79;Vine 1400 129 101
Arrow 1283 233 1347 216 '#76c7e4' $true;Arrow 1362 225 1483 262 '#76c7e4' $true
Text 1463 298 '终点 / 回程' 14 '#99d4be'
# B1 rising route, vines increase in elevation.
Platform 36 605 81;Platform 285 542 92
Vine 138 454 131;Vine 226 422 121;Vine 328 436 75
Arrow 301 529 227 516 '#76c7e4' $true;Arrow 210 505 139 474 '#76c7e4' $true
Arrow 140 466 162 416 '#76c7e4' $true;Arrow 159 346 116 281 '#76c7e4' $true
# B2 arena is a key stable exception. Entry/exit remain crumble.
Zone 452 445 295 135 '#ed8580' '战斗区域 · 稳定主场地'
Platform 433 584 51;Platform 491 560 217 $true;Platform 722 539 61
Text 510 499 '留出水平战斗净空' 17 '#e6c1b7'
Text 525 587 '两侧进出 / 中央作战' 14 '#99d4be'
Vine 755 429 84;Vine 454 433 129
Arrow 753 529 715 548;Arrow 498 548 471 572
# B3 descending/returning chain with a lower catch.
Platform 828 548 62;Platform 967 605 69;Platform 1097 517 75
Vine 905 430 109;Vine 1026 438 114;Vine 1135 434 59
Arrow 1111 505 1039 526 '#76c7e4' $true;Arrow 1002 547 917 518 '#76c7e4' $true;Arrow 900 526 861 536 '#76c7e4' $true
# B4 climbing transfer, hanging vines rather than grapple points.
Platform 1231 580 71;Platform 1370 617 56;Platform 1462 478 91
Vine 1323 445 113;Vine 1421 421 99;Vine 1511 434 22
Vine 1485 506 210
Arrow 1284 568 1334 530 '#76c7e4' $true;Arrow 1340 522 1425 488 '#76c7e4' $true;Arrow 1435 482 1491 466 '#76c7e4' $true
# A1: stable entry and a short first swing.
Platform 38 864 111 $true;Platform 256 845 74;Platform 351 875 26
Text 48 819 '入口 ← 风区' 19 '#e1ce76'
Vine 181 734 112;Vine 289 725 92
Arrow 139 851 189 820 '#76c7e4' $true;Arrow 206 829 271 833 '#76c7e4' $true
# A2: reserved simple puzzle, no extra puzzle imposed yet.
Zone 452 737 290 118 '#c1c87c' '普通解谜 · 空间预留'
Text 480 785 '机关方案待定 / 可安全观察' 16 '#c7d2b0'
Platform 433 875 63;Platform 511 855 166 $true;Platform 703 861 78
Vine 750 722 106
Text 531 883 '永久操作台' 15 '#99d4be'
# A3: two uninterrupted vine transfers over crumbling catches.
Platform 828 860 72;Platform 968 899 58;Platform 1099 846 74
Vine 919 724 111;Vine 1040 715 122;Vine 1152 731 86
Arrow 891 848 943 827 '#76c7e4' $true;Arrow 963 843 1037 815 '#76c7e4' $true;Arrow 1059 828 1129 834 '#76c7e4' $true
# A4 stable root portal; next vines take main route upward.
Platform 1223 846 69;Platform 1340 889 130 $true;Platform 1512 800 42
Vine 1317 738 116;Vine 1460 722 98;Vine 1528 714 61
Text 1347 911 '出口 ↓ 根区' 18 '#e1ce76'
Arrow 1284 834 1350 877 '#76c7e4' $true;Arrow 1448 877 1506 791 '#76c7e4' $true
Arrow 1505 774 1487 704 '#76c7e4' $true;Arrow 1485 638 1427 607 '#76c7e4' $true

# Cross-screen arrows: A1->A2->A3->A4->B4->B3->B2->B1->C1->C2->C3->C4.
Arrow 379 876 427 876 '#d6e4e6';Arrow 783 860 823 860 '#d6e4e6';Arrow 1174 847 1218 847 '#d6e4e6'
Arrow 1528 702 1528 638 '#d6e4e6';Arrow 1217 555 1178 555 '#d6e4e6';Arrow 822 548 786 548 '#d6e4e6';Arrow 427 583 380 583 '#d6e4e6'
Arrow 67 369 67 337 '#d6e4e6';Arrow 379 252 428 252 '#d6e4e6';Arrow 773 228 823 228 '#d6e4e6';Arrow 1168 245 1218 245 '#d6e4e6'

Line 20 948 1580 948 '#42606a' 1
Platform 26 983 83;Text 122 970 '普通枝台：踩上后延迟坍塌' 18
Platform 505 983 83 $true;Text 600 970 '关键永久落脚点' 18
Vine 917 963 45;Text 947 970 '已有悬挂藤蔓：抓藤身摆荡' 18
Arrow 29 1041 108 1041 '#76c7e4' $true;Text 122 1025 '虚线：摆荡 / 松手转移方向' 18
Arrow 511 1041 589 1041 '#d6e4e6';Text 601 1025 '实线：跨屏主路线' 18
Text 915 1025 '仅为路线草图；间距待摆荡原型校准' 17 '#91aab2'
[void]$svg.AppendLine('</svg>')
$bitmap.Save((Join-Path $outDir 'vine_map_layout_v1.png'),[System.Drawing.Imaging.ImageFormat]::Png)
[System.IO.File]::WriteAllText((Join-Path $outDir 'vine_map_layout_v1.svg'),$svg.ToString(),[System.Text.UTF8Encoding]::new($false))
$g.Dispose();$bitmap.Dispose()
Write-Output 'Vine map layout PNG and editable SVG saved.'
