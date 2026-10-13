extends SceneTree

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var camera: Camera2D
var feedback: CombatFeedbackService
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick(count: int, speed := 1.0) -> void:
	for i in count:
		boss._physics_process(speed / 60.0)
		boss.vfx._process(speed / 60.0)
		room._process(speed / 60.0)
func until(predicate: Callable, count := 1200) -> bool:
	for i in count:
		if predicate.call(): return true
		tick(1)
	return bool(predicate.call())
func capture(name: String) -> void:
	if output.is_empty(): return
	# The phase handoffs are manually ticked here; settle the one-real-second
	# mist fade that would already have finished during a normal playthrough.
	if boss.phase > 1:
		if room.mist_field._fade_tween != null and room.mist_field._fade_tween.is_valid():
			room.mist_field._fade_tween.kill()
		room.mist_field.modulate.a = 0.0
	feedback.clear_body_reaction(boss.animated_sprite)
	feedback.screen_fx.clear()
	feedback._reset_punch()
	room._process(0)
	camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	feedback = root.get_node("CombatFeedback") as CombatFeedbackService
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.NONE)
	var vine_reference = load("res://scenes/sideview/chapter_1_vine_room.tscn").instantiate()
	var reference_zoom: Vector2 = vine_reference.get_node("Camera2D").zoom
	vine_reference.free()
	check(reference_zoom == Chapter1VineRoom.CAMERA_ZOOM, "target framing matches the authored vine-region camera")
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	boss = room.deer; camera = room.get_node("Camera2D")
	boss.set_physics_process(false); boss.vfx.set_process(false); room.player.set_physics_process(false)
	room.player.reset_after_map_fall(Vector2(1250, 555))
	room._process(0)
	check(camera.zoom == Vector2.ONE, "mist starts at the existing close combat distance")
	var foreground := room.get_node("ArenaForeground") as Sprite2D
	var original_foreground_scale := foreground.scale
	var original_root_bottom := foreground.position.y + (room.arena_foreground_root_bottom - foreground.texture.get_height() * 0.5) * foreground.scale.y
	for phase in [1, 2]:
		boss.combat_stats.apply_health_damage(boss.combat_stats.health)
		check(until(func() -> bool: return not boss.phase_transition.active), "handoff %d completes" % phase)
		check(camera.zoom == Vector2.ONE, "phase %d handoff keeps the original framing" % phase)
	room.player.reset_after_map_fall(Vector2(1250, 555))
	room._process(0)
	await capture("01_before_transform")
	boss.combat_stats.apply_health_damage(boss.combat_stats.health)
	check(until(func() -> bool: return boss.phase_transition.stage == &"roar"), "wind-to-vine roar starts")
	check(boss.phase == 4 and camera.zoom == Vector2.ONE, "phase announcement does not zoom out before the actual transformation")
	check(until(func() -> bool: return boss.vine_phase.step == DeerVinePhase.Step.TRANSFORM), "actual human transformation starts")
	room.player.reset_after_map_fall(Vector2(1250, 555))
	room._process(0)
	var previous := camera.zoom.x
	var monotonic := true
	var largest_step := 0.0
	for i in 48:
		tick(1)
		if camera.zoom.x > previous + 0.000001: monotonic = false
		largest_step = maxf(largest_step, absf(previous - camera.zoom.x))
		previous = camera.zoom.x
	check(is_equal_approx(camera.zoom.x, 0.9), "camera is halfway between combat and vine distance halfway through the 1.6-second transform")
	await capture("02_transform_midpoint")
	var held := camera.zoom
	boss.red_parry_hold = true
	tick(30)
	check(camera.zoom.is_equal_approx(held), "action-clock pause also pauses the zoom transition")
	boss.red_parry_hold = false
	var clock_before := boss.vine_phase._time
	tick(12, 0.25)
	check(is_equal_approx(boss.vine_phase._time - clock_before, 0.05) and camera.zoom.x < held.x and camera.zoom.x > reference_zoom.x, "quarter-speed transformation slows the camera with the animation")
	check(until(func() -> bool: return boss.vine_phase.step == DeerVinePhase.Step.HOVER), "transformation and ascent finish")
	check(monotonic and largest_step < 0.004, "zoom eases monotonically without abrupt frame-to-frame jumps")
	check(camera.zoom.is_equal_approx(reference_zoom), "hovering boss retains exactly the vine-region distance")
	check(room._camera_view_size.is_equal_approx(Vector2(1600, 900)), "wide camera shows 1600 by 900 world pixels")
	check(foreground.scale.is_equal_approx(original_foreground_scale * 1.25), "expanded foreground preserves its authored width-to-height ratio")
	var wide_root_bottom := foreground.position.y + (room.arena_foreground_root_bottom - foreground.texture.get_height() * 0.5) * foreground.scale.y
	check(is_equal_approx(wide_root_bottom, original_root_bottom), "foreground roots retain their measured ground anchor throughout the pullback")
	camera.force_update_scroll()
	check(camera.limit_top == -180 and is_equal_approx(camera.get_screen_center_position().y, 270), "camera reveals extra sky and keeps the arena bottom fixed")
	await capture("03_hover_wide")
	room.player.position.x = 48
	room._process(0)
	check(is_equal_approx(camera.position.x, 800) and is_zero_approx(room._camera_travel), "left boundary accounts for the wider visible area")
	room.player.position.x = 2512
	room._process(0)
	check(is_equal_approx(camera.position.x, 1760) and is_equal_approx(room._camera_travel, 960), "right boundary and parallax account for the wider visible area")
	await capture("04_right_edge_wide")
	room.player.position.x = 1250
	room._process(0)
	feedback.request_camera_punch(0.11)
	room._process(0)
	check(camera.zoom.x > reference_zoom.x and room._camera_view_size.is_equal_approx(Vector2(1600, 900)), "shared parry camera punch stays layered over stable room framing")
	feedback._update_punch(CombatFeedbackService.PUNCH_DURATION)
	room._process(0)
	check(camera.zoom.is_equal_approx(reference_zoom), "camera punch returns to vine distance rather than the old combat zoom")
	boss.vine_phase.shield = 0
	boss.vine_phase._begin_fall()
	check(until(func() -> bool: return boss.vine_phase.step == DeerVinePhase.Step.STAGGER), "caster falls into its ground damage window")
	check(camera.zoom.is_equal_approx(reference_zoom), "ground window keeps the wide flight camera")
	await capture("05_ground_window_wide")
	check(until(func() -> bool: return boss.vine_phase.step == DeerVinePhase.Step.HOVER), "caster rises for its next round")
	check(camera.zoom.is_equal_approx(reference_zoom), "rise and next round preserve vine framing")
	boss.combat_stats.apply_health_damage(boss.combat_stats.health)
	check(until(func() -> bool: return boss.state == DeerBoss.State.COMPLETE), "fourth-phase defeat completes")
	check(camera.zoom.is_equal_approx(reference_zoom), "completed encounter retains the wide framing")
	room._revive()
	await process_frame; await process_frame
	boss.set_physics_process(false)
	room._process(0)
	check(boss.phase == 1 and camera.zoom.is_equal_approx(Vector2.ONE) and camera.limit_top == 0, "retry restores normal framing and clears the expanded sky limit")
	await capture("06_retry_normal")
	# Ensure a punch active during a new transform tracks the moving base zoom.
	boss.phase = 4
	boss.reset_phase()
	room._process(0)
	feedback.request_camera_punch(0.05)
	tick(48)
	feedback._reset_punch()
	check(is_equal_approx(camera.zoom.x, 0.9), "an overlapping punch cannot restore a stale zoom during transformation")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "camera checks do not modify story progress")
	room.queue_free()
	await process_frame; await process_frame
	await create_timer(0.3, true, false, true).timeout
	print("VINE_CAMERA: %d checks, %d failures" % [checks, failures])
	call_deferred("quit", 1 if failures else 0)
