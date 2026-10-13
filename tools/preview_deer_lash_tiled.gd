extends SceneTree
## Isolated visual inspection of the same ribbon now used by the real skill.
const Ribbon = preload("res://scripts/sideview/deer_vine_lash_ribbon.gd")
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room
var boss: DeerBoss
var ribbon
var output := ""
var live := false
var animation_paused := false
var elapsed := 0.0
var direction := 1.0
var caption: Label
var failures := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var production := "--production" in args
	live = "--live" in args
	if not args.is_empty() and not args[0].begins_with("--"):
		output = args[0]
		DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var scene := "res://scenes/sideview/chapter_1_final_boss_room.tscn" if production else "res://scenes/dev/boss_development_room.tscn"
	room = load(scene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	boss = room.deer if production else room.adapter.deer
	boss.set_physics_process(false)
	boss.vfx.set_process(false)
	if production:
		room.player.reset_after_map_fall(Vector2(1250,555))
		boss.phase = 4
		boss.reset_phase()
		boss.manual_control = true
	else:
		room.select_combo(4)
		room.play_action(0)
	var reached_hover := false
	for i in 600:
		boss._physics_process(1.0 / 60.0)
		boss.vfx._process(1.0 / 60.0)
		if boss.vine_phase.step == DeerVinePhase.Step.HOVER:
			reached_hover = true
			break
	if not reached_hover:
		push_error("Transformation did not finish")
		quit(1)
		return
	room._process(0)
	var camera := root.get_camera_2d()
	if camera != null: camera.force_update_scroll()
	var zoom := camera.zoom.x if camera != null else 1.0
	var center := camera.get_screen_center_position().x if camera != null else 640.0
	var width := root.get_visible_rect().size.x / zoom
	ribbon = Ribbon.new()
	boss.add_child(ribbon)
	ribbon.top_level = true
	ribbon.global_position = Vector2.ZERO
	ribbon.z_index = SideviewLayers.EFFECT
	ribbon.setup(Vector2(center - width * 0.4, 555), 1, width * 0.8)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(18, 160 if not production else 132)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color("f1e6a5"))
	caption.add_theme_color_override("font_outline_color", Color("182018"))
	caption.add_theme_constant_override("outline_size", 6)
	overlay.add_child(caption)
	if live:
		root.window_input.connect(_on_window_input)
		return
	for facing in [1.0,-1.0]:
		ribbon.direction = facing
		ribbon.origin.x = center - facing * width * 0.4
		for frame in [7,10,12,15,18,23]:
			var seconds: float = ribbon._frame_starts[frame]
			ribbon.sample(seconds)
			caption.text = "局部贴图拼接 · 细藤预览 · F%02d · 无伤害演示" % frame
			await capture(("right" if facing > 0 else "left") + "_f%02d" % frame)
			for strand in ribbon.paths.size():
				var path: PackedVector2Array = ribbon.paths[strand]
				var width_: float = ribbon.thickness * (0.76 if strand == 0 else 1.0)
				var planted: Vector2 = ribbon.origin + Vector2(0,width_ * 0.6)
				if path[0].distance_to(planted) > 0.001: failures += 1
				for p in path:
					if not p.is_finite(): failures += 1
			ribbon.sample(ribbon.total_time())
		if not ribbon.paths.is_empty(): failures += 1
	print("TILED_LASH_PREVIEW: pinned roots, finite curves, left/right and retraction; failures=", failures)
	quit(1 if failures else 0)

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if not output.is_empty():
		root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func _process(delta: float) -> bool:
	if not live or ribbon == null or animation_paused: return false
	elapsed += minf(delta,0.05)
	var period: float = ribbon.total_time() + 1.5
	var cycle := int(elapsed / period)
	var camera := root.get_camera_2d()
	var zoom := camera.zoom.x if camera != null else 1.0
	var center := camera.get_screen_center_position().x if camera != null else 640.0
	var width := root.get_visible_rect().size.x / zoom
	direction = 1 if cycle % 2 == 0 else -1
	ribbon.direction = direction
	ribbon.origin.x = center - direction * width * 0.4
	var time_ := fmod(elapsed,period) - 0.75
	ribbon.sample(time_)
	caption.text = "局部贴图拼接 · 细藤预览 · 无伤害演示\nSpace 暂停   ← / → 调整粗细   Esc 退出"
	return false

func _on_window_input(event: InputEvent) -> void:
	if not live: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: quit()
		elif event.keycode == KEY_SPACE: animation_paused = not animation_paused
		elif event.keycode == KEY_LEFT: ribbon.thickness = maxf(24,ribbon.thickness - 8)
		elif event.keycode == KEY_RIGHT: ribbon.thickness = minf(112,ribbon.thickness + 8)
