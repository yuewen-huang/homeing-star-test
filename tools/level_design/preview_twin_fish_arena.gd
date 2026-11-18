extends "../../tests/support/harness.gd"
## Formal-map entry, always with isolated in-memory progress.
const SCENE := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"
var level: SunkenCavern
var output := ""

class OpeningRecorder extends Node:
	var folder := ""
	var age := 0.0
	var next_sample := 0.0
	var frames: Array[Dictionary] = []
	func _process(delta: float) -> void:
		age += delta
		if age < next_sample: return
		next_sample = age + 1.0 / 15.0
		_sample(age)
	func _sample(at: float) -> void:
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		var filename := "%04d.png" % frames.size()
		var frame := get_viewport().get_texture().get_image()
		frame.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		frame.save_png(folder.path_join(filename))
		frames.append({"file": filename, "time": at})
	func _exit_tree() -> void:
		var manifest := FileAccess.open(folder.path_join("frames.json"), FileAccess.WRITE)
		manifest.store_string(JSON.stringify(frames))

func verifying() -> bool:
	return "--verify" in OS.get_cmdline_user_args()

func make_recorder() -> OpeningRecorder:
	return OpeningRecorder.new()

func run() -> void:
	use_memory_progress()
	var args := OS.get_cmdline_user_args()
	var option := args.find("--capture-dir")
	if option >= 0:
		output = args[option + 1]
		DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	var four_symbols := "--four-symbols" in args
	if four_symbols:
		level.twin_fish_encounter.opening_movement = TwinFishBoss.LightningDuel.Movement.FOUR_SYMBOLS
	level.player.reset_after_map_fall(Vector2(8310, 5374))
	level.snap_camera()
	root.title = "归航星 · 两仪生四象" if four_symbols else "归航星 · 双子正式战场 · 古城幻化"
	await wait_frames(3)
	if "--record" in args and not output.is_empty():
		var recorder := make_recorder()
		recorder.folder = output.path_join("frames")
		DirAccess.make_dir_recursive_absolute(recorder.folder)
		level.add_child(recorder)
	if not verifying():
		print("TWIN_FISH_FORMAL_ARENA_READY: walk right to start")
		return
	await verify_opening()

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func verify_opening() -> void:
	var opening := level.twin_fish_encounter
	var arena := opening.arena
	var initial_zoom := level.camera.zoom
	check(not opening.engaged, "Entry approach does not seal the room prematurely")
	await capture("00_ruins")
	Input.action_press(&"ui_right")
	for frame in 100:
		await physics_frame
		if opening.engaged: break
	Input.action_release(&"ui_right")
	check(opening.engaged, "Walking into the formal room starts the opening")
	if not opening.engaged:
		finish("TWIN FISH FORMAL OPENING")
		return
	check(opening.seals.size() == 4 and level.player.input_frozen, "Four physical seals close and opening owns input")
	check(opening.layers.size() == 3, "Far, middle and near paintings are separate layers")
	var handed_off := [0]
	opening.battle_started.connect(func(): handed_off[0] += 1)
	var previous_reveal := Vector3.ZERO
	var continuous := true
	var no_early_fish := true
	var saved_mid := false
	var saved_fish := false
	var saved_chaos := false
	var checked_origin := false
	var previous_camera := level.camera.position
	var max_camera_step := 0.0
	var previous_fish_age := -1.0
	var previous_white := Vector2.ZERO
	var previous_black := Vector2.ZERO
	var continuous_fish := true
	var moving_samples := 0
	for frame in 800:
		await physics_frame
		for index in 3:
			var value: float = opening.layers[index].material.get_shader_parameter(&"reveal")
			continuous = continuous and value >= previous_reveal[index] and value - previous_reveal[index] < 0.08
			previous_reveal[index] = value
		max_camera_step = maxf(max_camera_step, previous_camera.distance_to(level.camera.position))
		previous_camera = level.camera.position
		if opening.age < opening.FISH_AT: no_early_fish = no_early_fish and not is_instance_valid(opening.fish)
		if is_instance_valid(opening.fish):
			var twin := opening.fish
			if previous_fish_age >= 3.65 and twin.arrival_age < 4.35:
				moving_samples += 1
				continuous_fish = continuous_fish and twin.white_swimmer.position.distance_to(previous_white) > 0.2 and twin.black_swimmer.position.distance_to(previous_black) > 0.2
			previous_fish_age = twin.arrival_age
			previous_white = twin.white_swimmer.position
			previous_black = twin.black_swimmer.position
		if opening.age >= 1.6 and not saved_mid:
			saved_mid = true
			await capture("01_restoring_city")
		if opening.age >= 5.2 and not saved_fish:
			saved_fish = true
			await capture("02_fish_entering")
		if is_instance_valid(opening.fish) and opening.fish._taichi_array.visible:
			var twin := opening.fish
			var field := twin._taichi_array
			if not checked_origin:
				checked_origin = true
				var white := twin.white_sprite.joint_in_boss(1).lerp(twin.white_sprite.joint_in_boss(2), 0.35)
				var black := twin.black_sprite.joint_in_boss(1).lerp(twin.black_sprite.joint_in_boss(2), 0.35)
				check(field.position.distance_to((black + white) * 0.5) < 6.0, "First ink appears between the passing fish")
			if twin._array_age >= 0.54 and not saved_chaos:
				saved_chaos = true
				await capture("03_first_brushstrokes")
		if opening.battle_ready: break
	check(continuous, "All three reveal envelopes are continuous and monotonic")
	check(max_camera_step < 20.0, "Camera approaches the field center without a positional cut")
	check(level.camera.zoom.is_equal_approx(initial_zoom), "Opening preserves the original camera distance")
	var screen_feet := level.player.get_global_transform_with_canvas().origin
	check(screen_feet.y > 0.0 and screen_feet.y < level.get_viewport_rect().size.y - 24.0, "Playing-scale camera keeps the character and ground visible")
	check(no_early_fish and is_instance_valid(opening.fish), "Both fish enter after the city has restored")
	check(continuous_fish and moving_samples >= 20, "Both fish keep swimming through the former formation pause")
	var skill_slots: Control = level.player.get_node("SkillBar/MarginContainer/Slots")
	check(screen_feet.y < skill_slots.get_global_rect().position.y - 16.0, "Feet stay above the real skill-bar frame with visible clearance")
	check(opening.battle_ready and handed_off[0] == 1 and not level.player.input_frozen, "Opening hands control back exactly once")
	if is_instance_valid(opening.fish):
		var field := opening.fish._taichi_array
		var paint := field.painted_bounds()
		paint.position += opening.fish.position
		var deck := opening.layers[2]
		var back_edge := deck.to_global(Vector2(0, opening.TERRACE_BACK_Y)).y
		var front_edge := deck.to_global(Vector2(0, opening.TERRACE_FRONT_Y)).y
		check(is_equal_approx(field.stage, 1.0), "Opening stops at the first Taiji stage")
		check(is_equal_approx(paint.size.x, paint.size.y) and is_equal_approx(paint.end.y, back_edge), "Round field rests on the upper edge of the terrace")
		check(absf(level.player.position.y + 2.0 - (back_edge + front_edge) * 0.5) < 1.0, "Lan stands on the paving centerline rather than the front lip")
		check(is_equal_approx(opening.layers[1].to_global(Vector2(0, opening.MIDDLE_BASE_Y)).y, back_edge), "Middle balustrade bases meet the terrace back edge")
		check(is_equal_approx(paint.size.x, 921.6), "Formal circle diameter is reduced by exactly ten percent")
		check(paint.position.y >= arena.position.y - 0.1, "Circle stays below the reserved battle ceiling")
		check(is_equal_approx(field._circle.body_opacity, 0.90), "Only the array body receives subtle transparency")
		check(field.active_core_positions().size() == 2 and is_equal_approx(field.modulate.a, 1.0), "Both eyes retain the original opacity while only the array body is softened")
		var screen_center := opening.fish.get_global_transform_with_canvas().origin
		check(screen_center.y >= 270.0 and screen_center.y <= 330.0, "Free-swim center is lowered into the standard battle view")
	await capture("04_taiji_battle_ready")
	Input.action_press(&"ui_left")
	var fish_stay_in_view := true
	for frame in 180:
		await physics_frame
		for sprite in [opening.fish.white_sprite, opening.fish.black_sprite]:
			var joints: PackedVector2Array = sprite.global_joints()
			var body := (joints[1] + joints[2]) * 0.5
			var screen_body := level.get_canvas_transform() * body
			fish_stay_in_view = fish_stay_in_view and screen_body.y >= 80.0 and screen_body.y <= screen_feet.y - 64.0
	Input.action_release(&"ui_left")
	check(level.player.position.x >= arena.position.x + 24.0, "Real movement cannot leave the sealed left edge")
	check(level.player.position.x < arena.position.x + 150.0, "Player can move normally after the opening")
	check(level.player.get_global_transform_with_canvas().origin.x >= 24.0, "Normal-distance camera follows edge movement without losing the player")
	check(fish_stay_in_view, "Both freely swimming bodies remain in the visible combat space")
	var count_before := opening.layers.size()
	level._on_drowned()
	for frame in 12: await physics_frame
	check(opening.engaged and not opening.battle_ready and level.player.input_frozen, "Death restarts the same opening safely")
	check(opening.layers.size() == count_before and opening.seals.size() == 4, "Retry reuses city layers and seals")
	await capture("05_retry")
	level.queue_free()
	await wait_frames(3)
	expect_save_untouched()
	finish("TWIN FISH FORMAL OPENING")
