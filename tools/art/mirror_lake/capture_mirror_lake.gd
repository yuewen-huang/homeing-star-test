extends SceneTree

## 镜湖真实渲染截图（不是 numpy 预览）。需要带窗口的 Godot（GL Compatibility），不能 --headless。
##
## 用法（窗口会被挪到屏幕外）：
##   Godot --path homeing-star-game --rendering-driver opengl3 --resolution 1280x720 --position -3000,0 \
##     --script homeing-star-test/tools/art/mirror_lake/capture_mirror_lake.gd -- <输出目录>
## 输出：<名字>.png —— strip_00..strip_11（每屏一张，拼长卷用）、start / entry / puzzle_one / puzzle_two / boss / boss_end / jump。

const SCENE_PATH := "res://scenes/levels/mirror_lake/mirror_lake.tscn"

var out_dir := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := (load(SCENE_PATH) as PackedScene).instantiate() as MirrorLake
	root.add_child(scene)
	await process_frame
	var shots: Array = []
	for k in 12:
		shots.append(["strip_%02d" % k, 640.0 + 1280.0 * k, 0.0])
	shots.append_array([
		["start", MirrorLake.SPAWN_X, 0.0],
		["entry", 2000.0, 0.0],
		["puzzle_one", 5100.0, 0.0],
		["puzzle_two", 10200.0, 0.0],
		["boss", MirrorLake.BOSS_ARENA_CENTER_X, 0.0],
		["boss_end", MirrorLake.WORLD_LENGTH - MirrorLake.PLAYER_MARGIN, 0.0],
		["jump", 5100.0, -170.0],
	])
	for shot in shots:
		var p := scene.player
		p.position = Vector2(shot[1], MirrorLake.STAND_Y + shot[2])
		p.velocity = Vector2.ZERO
		for i in 40:
			scene._process(0.05)
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, shot[0]])
		print("saved ", shot[0], " x=", shot[1], " cam=", scene.camera_x, " zone=", MirrorLake.ZONE_NAMES[MirrorLake.zone_at(shot[1])])
	quit(0)
