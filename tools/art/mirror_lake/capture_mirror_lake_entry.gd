extends SceneTree

## 镜湖入口区截图：拱桥+多丛芦苇门、阳态缺口见印影、阴态盖印、桥上跳被挡、开门后。
##
## 用法（需要带窗口渲染，不用 --headless）：
##   Godot --path homeing-star-game --rendering-driver opengl3 --resolution 1280x720 --position -3000,0 \
##     --script homeing-star-test/tools/art/mirror_lake/capture_mirror_lake_entry.gd -- <输出目录>

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
	print("saved ", file_name, " side=", scene.side, " gate_open=", scene.entry.gate_open if scene.entry else false,
		" player_x=", scene.player.position.x, " seal_a=", scene.entry.seal.modulate.a if scene.entry else -1)


func step(seconds: float) -> void:
	scene._process(seconds)


func settle(frames: int = 24) -> void:
	for i in frames:
		step(0.05)
		await process_frame


func place(x: float, y: float = -1.0) -> void:
	if y < 0.0:
		y = MirrorLake.STAND_Y
	scene.player.position = Vector2(x, y)
	scene.player.velocity = Vector2.ZERO


func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = (load(SCENE_PATH) as PackedScene).instantiate() as MirrorLake
	root.add_child(scene)
	await process_frame
	scene.set_process(false)

	# 1) 阳态：站在右桥段看多丛芦苇门封路（特写）
	place(MirrorLakeEntry.GATE_X - 120.0, MirrorLakeEntry.BRIDGE_DECK_Y)
	scene.entry.refresh_seal_visibility()
	await settle()
	await shoot("01_yang_reed_clusters_gate")

	# 2) 阳态：站在左桥缺口边，俯看水下印影（缺口对印）
	place(MirrorLakeEntry.bridge_left_end() - 40.0, MirrorLakeEntry.BRIDGE_DECK_Y)
	await settle()
	await shoot("02_yang_gap_seal_ghost")

	# 2b) 阳态：左桥中段看拱桥全貌（缺口+右段）
	place((MirrorLakeEntry.BRIDGE_LEFT_X + MirrorLakeEntry.bridge_left_end()) * 0.5, MirrorLakeEntry.BRIDGE_DECK_Y)
	await settle()
	await shoot("02b_yang_arch_bridge_overview")

	# 2c) 阳态：桥上「二段跳高度」仍被门挡（示意：脚在接近 DJ 顶点）
	place(MirrorLakeEntry.GATE_X - 80.0, MirrorLakeEntry.bridge_double_jump_peak_y() + 12.0)
	await settle()
	await shoot("02c_yang_bridge_dj_blocked")

	# 3) 阴态：缺口落点印清晰
	scene.request_switch()
	step(MirrorLake.SWITCH_DURATION + 0.05)
	place(MirrorLakeEntry.SEAL_X - 90.0, MirrorLake.STAND_Y)
	scene.entry.refresh_seal_visibility()
	await settle()
	await shoot("03_yin_gap_seal_clear")

	# 4) 踩印开门
	place(MirrorLakeEntry.SEAL_X)
	scene.entry.tick(0.05)
	step(0.05)
	for i in 12:
		scene.entry.tick(MirrorLakeEntry.GATE_OPEN_DURATION / 10.0)
		step(0.05)
		await process_frame
	place(MirrorLakeEntry.GATE_X - 160.0, MirrorLakeEntry.BRIDGE_DECK_Y)
	await settle()
	await shoot("04_gate_open")

	# 5) 过门
	place(MirrorLake.ZONE_PUZZLE_ONE_START + 80.0)
	await settle()
	await shoot("05_past_gate")

	quit(0)
