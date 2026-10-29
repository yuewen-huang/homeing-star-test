extends SceneTree

## 镜湖真实渲染截图（不是 numpy 预览）。需要带窗口的 Godot（GL Compatibility），不能 --headless。
##
## 用法（窗口会被挪到屏幕外）：
##   Godot --path homeing-star-game --rendering-driver opengl3 --resolution 1280x720 --position -3000,0 \
##     --script homeing-star-test/tools/art/mirror_lake/capture_mirror_lake.gd -- <输出目录>
## 输出：<名字>.png —— strip_00..（每屏一张，屏数 = WORLD_LENGTH / 1280，拼长卷用）、start / entry / puzzle_one / puzzle_two / boss / boss_end / jump。

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
	print_extents(scene)
	for k in int(MirrorLake.WORLD_LENGTH / MirrorLake.VIEW_WIDTH):
		shots.append(["strip_%02d" % k, 640.0 + 1280.0 * k, 0.0])
	shots.append_array([
		["start", MirrorLake.SPAWN_X, 0.0],
		["entry", 2000.0, 0.0],
		["puzzle_one", 5700.0, 0.0],
		["puzzle_two", 10400.0, 0.0],
		["boss", MirrorLake.BOSS_ARENA_CENTER_X, 0.0],
		["boss_end", MirrorLake.WORLD_LENGTH - MirrorLake.PLAYER_MARGIN, 0.0],
		["jump", 5700.0, -170.0],
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


## Prints the real world-x extents of every gameplay element (visible sprite rects), for layout checks.
func print_extents(scene: MirrorLake) -> void:
	for n in [scene.entry, scene.shadow_bridge, scene.puzzle_stele, scene.ink_carp, scene.lotus, scene.ink_trial, scene.panda_arena]:
		var lo := INF
		var hi := -INF
		for s in n.find_children("*", "Sprite2D", true, false):
			var sp := s as Sprite2D
			if not sp.is_visible_in_tree() or sp.texture == null: continue
			var r := sp.get_global_transform() * sp.get_rect()
			lo = minf(lo, r.position.x)
			hi = maxf(hi, r.end.x)
		print("EXTENT ", n.name, " ", n.global_position.x, " ", lo, " ", hi)
	for b in scene.shadow_bridge.bridges:
		print("BRIDGE origin=", b.origin.x, " deck=", b.origin.x + 48.0 * b.scale, "..", b.origin.x + 1724.0 * b.scale)
