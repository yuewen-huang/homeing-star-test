extends SceneTree
## 镜湖墨鲤打鱼截图（窗口 Godot / GL Compatibility）。

const SCENE_PATH := "res://scenes/levels/mirror_lake/mirror_lake.tscn"
var out_dir := "."

class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)

	var scene := (load(SCENE_PATH) as PackedScene).instantiate() as MirrorLake
	root.add_child(scene)
	await process_frame
	var carp := scene.ink_carp
	var player := scene.player as LanPlayer
	print("carp visible=", carp.visible, " x=", carp.position.x)

	player.position = Vector2(carp.position.x - 90.0, MirrorLake.STAND_Y)
	player.velocity = Vector2.ZERO
	for i in 36:
		scene._process(0.05)
		await process_frame
	await _shot(scene, "carp_hopping")

	carp.enter_flop()
	player.position = Vector2(carp.position.x - 90.0, MirrorLake.STAND_Y)
	for i in 24:
		scene._process(0.05)
		await process_frame
	await _shot(scene, "carp_flopping")

	carp.hits_left = 1
	carp.receive_hit(1, player.global_position)
	print("seal visible=", carp.seal_sprite.visible, " parent=", carp.visible, " seal_global=", carp.seal_sprite.global_position)
	player.position = Vector2(carp.position.x - 150.0, MirrorLake.STAND_Y)
	for i in 24:
		scene._process(0.05)
		await process_frame
	await _shot(scene, "carp_seal_drop")

	player.position = Vector2(carp.position.x - 110.0, MirrorLake.STAND_Y)
	for i in 16:
		scene._process(0.05)
		await process_frame
	await _shot(scene, "carp_seal_near")

	print("ink carp captures done -> ", out_dir)
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	quit(0)

func _shot(scene: MirrorLake, shot_name: String) -> void:
	for i in 20:
		scene._process(0.05)
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, shot_name])
	print("saved ", shot_name, " player=", scene.player.position.x, " carp=", scene.ink_carp.position.x, " cam=", scene.camera_x)
