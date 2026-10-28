extends SceneTree

## 镜湖「阴阳切换」（黑白互换，几何不变）过渡关键帧截图（真实渲染，需要带窗口的 Godot，不能 --headless）。
##
## 用法：
##   Godot --path homeing-star-game --rendering-driver opengl3 --resolution 1280x720 --position -3000,0 \
##     --script homeing-star-test/tools/art/mirror_lake/capture_mirror_lake_switch.gd -- <输出目录>
## 输出：switch_00_before / 01_p10 / 02_p25 / 03_p40 / 04_p50 / 05_p60 / 06_p75 / 07_p90 / 08_yin / 09_back_yang，
##       以及阳面的 yang_start / yang_boss / yang_jump、阴面的 yin_start / yin_boss / yin_jump（日月互换：阳=日，阴=月）。

const SCENE_PATH := "res://scenes/levels/mirror_lake/mirror_lake.tscn"

var out_dir := "."
var scene: MirrorLake


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	call_deferred("run")


func shoot(file_name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, file_name])
	print("saved ", file_name, " progress=", scene.transition_progress(), " side=", scene.side, " cam_y=", scene.camera_y, " player_y=", scene.player.position.y)


## 手动推进（不让引擎自己跑 _process，截图才可重复）。
func step(seconds: float) -> void:
	scene._process(seconds)


func settle(frames: int = 30) -> void:
	for i in frames:
		step(0.05)
		await process_frame


func place(x: float, lift: float = 0.0) -> void:
	scene.player.position = Vector2(x, MirrorLake.STAND_Y - lift)
	scene.player.velocity = Vector2.ZERO


func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = (load(SCENE_PATH) as PackedScene).instantiate() as MirrorLake
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	place(5100.0)
	await settle()
	await shoot("switch_00_before")
	# 阳面其它镜头位置（日、月随远景层，屏幕位置固定；起点 / boss 区 / 跳起抬高镜头）
	place(420.0)
	await settle()
	await shoot("yang_start")
	place(MirrorLake.BOSS_ARENA_CENTER_X)
	await settle()
	await shoot("yang_boss")
	place(5100.0, 170.0)
	for i in 6:
		step(0.05)
	await shoot("yang_jump")
	place(5100.0)
	await settle()
	scene.request_switch()
	var d := MirrorLake.SWITCH_DURATION
	var last := 0.0
	for spec in [["switch_01_p10", 0.10], ["switch_02_p25", 0.25], ["switch_03_p40", 0.40], ["switch_04_p50", 0.50],
			["switch_05_p60", 0.60], ["switch_06_p75", 0.75], ["switch_07_p90", 0.90]]:
		step((spec[1] - last) * d)
		last = spec[1]
		await shoot(spec[0])
	step((1.0 - last) * d + 0.001)
	await settle()
	await shoot("switch_08_yin")
	step(MirrorLake.SWITCH_COOLDOWN + 0.1)
	scene.request_switch()
	step(d * 0.5)
	await shoot("switch_09_back_mid")
	step(d * 0.5 + 0.001)
	await settle()
	await shoot("switch_10_back_yang")
	# 阴面的其它位置
	step(MirrorLake.SWITCH_COOLDOWN + 0.1)
	scene.request_switch()
	step(d + 0.001)
	place(420.0)
	await settle()
	await shoot("yin_start")
	place(MirrorLake.BOSS_ARENA_CENTER_X)
	await settle()
	await shoot("yin_boss")
	place(5100.0, 170.0)
	scene.player.velocity = Vector2.ZERO
	for i in 6:
		step(0.05)
	await shoot("yin_jump")
	quit(0)
