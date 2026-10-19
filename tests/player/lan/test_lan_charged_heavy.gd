extends SceneTree
## Input-level heavy / throw regression, optional production-background captures.
class LocalProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var failures := 0
var checks := 0
var capture := false
var out := ""
var recorded_frames := 0
var capture_tick := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func shot(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
func record_frame() -> void:
	if not capture: return
	capture_tick += 1
	if capture_tick % 3 != 0: return
	await shot("frame_%04d" % recorded_frames)
	recorded_frames += 1
func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	out = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var progress := LocalProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var room = load("res://scenes/sideview/tutorial_battle_room.tscn").instantiate()
	var background: Node = room.get_node("Environment")
	room.remove_child(background)
	room.free()
	world.add_child(background)
	var camera := Camera2D.new()
	camera.position = Vector2(0, 360)
	world.add_child(camera)
	camera.make_current()
	var player = load("res://scenes/sideview/lan_player.tscn").instantiate()
	player.position = Vector2(-40, 555)
	player.world_min_x = -1800.0
	player.world_max_x = 1800.0
	world.add_child(player)
	player.set_physics_process(false)
	await process_frame
	check(player.heavy_charge_visual is Sprite2D and player.heavy_charge_visual.get_child_count() == 0, "Runtime charge uses one sprite, with no procedural render nodes")
	var charge_pose: Texture2D = player.animated_sprite.sprite_frames.get_frame_texture(&"special_attack", 4)
	var expected_pivot: Vector2 = Vector2(charge_pose.get_image().get_used_rect().get_center()) - charge_pose.get_size() * 0.5
	check(expected_pivot == player.heavy_charge_visual.POSE_CENTER, "Baked pivot matches the actual charge body pose")
	Input.action_press(&"special_attack")
	player._physics_process(1.0 / 60.0)
	check(player.special_attack_charging, "I input begins charging")
	for i in 65:
		player._physics_process(1.0 / 60.0)
		if i == 15: await shot("heavy_charge_early")
		if i == 35: await shot("heavy_charge_mid")
		await record_frame()
	check(player.special_attack_charging and player.timeline_attack_effect == null, "Holding beyond full charge causes no hit or automatic release")
	await shot("heavy_charge")
	check(player.heavy_charge_visual.charging and player.heavy_charge_visual.frame >= player.heavy_charge_visual.CHARGE_FRAMES, "Baked charge reaches the full-charge frame sequence")
	Input.action_release(&"special_attack")
	player._physics_process(1.0 / 60.0)
	check(not player.special_attack_charging and player.special_attack_charge_ratio == 1.0, "Releasing I commits full charge")
	check(player.heavy_charge_visual.reached_full, "Full charge produces the local four-ray glint")
	var start_x: float = player.position.x
	var ghosts := 0
	for i in 30:
		player._physics_process(1.0 / 60.0)
		for child in world.get_children():
			if child is LanUltimateAfterimage: ghosts += 1
		if player.special_attack_lunge_elapsed > 0.04 and player.special_attack_lunge_elapsed < 0.09:
			await shot("heavy_lunge")
		await record_frame()
		await process_frame
	check(is_equal_approx(absf(player.position.x - start_x), 300.0), "Full charge moves exactly 300 px in the real movement loop")
	check(ghosts > 0, "Full-charge movement emits body afterimages")
	await shot("heavy_recovery")
	check(not player.heavy_charge_visual.charging and not player.heavy_charge_visual.visible, "Release clears all charge-only VFX during recovery")
	player.end_special_attack_early()
	player.position = Vector2(-40, 555)
	player.facing_direction = 1.0
	player.apply_facing_direction()
	var dummy = load("res://scenes/sideview/training_dummy.tscn").instantiate()
	dummy.position = Vector2(120, 555)
	world.add_child(dummy)
	dummy.set_process(false)
	dummy.combat_stats.poise = 0
	await process_frame
	player.update_throw_prompt()
	check(player.find_throw_target() == dummy and player.throw_prompt.visible, "Broken target in front offers E")
	await shot("throw_available")
	check(player.throw_prompt is KeyHint and player.throw_prompt.key_nodes.size() == 1, "E uses the shared breathing keycap component")
	check(player.throw_prompt.pending_actions == [&"interact"], "E keycap resolves the current interaction binding")
	for i in 20: await record_frame()
	Input.action_press(&"interact")
	player._physics_process(1.0 / 60.0)
	Input.action_release(&"interact")
	check(player.special_attack_max_form and not player.special_attack_charging, "E immediately selects the old PLUS attack")
	check(player.timeline_attack_effect.skill_hit_context.damage == 60 and player.timeline_attack_effect.skill_hit_context.max_form, "E preserves PLUS damage and suppression contract")
	player.end_special_attack_early()
	dummy.position.x = -500
	check(player.find_throw_target() == null, "Broken enemies behind the player cannot activate E")
	dummy.position.x = 300
	check(player.find_throw_target() == null, "Distant broken enemies cannot activate E")
	dummy.position.x = 120
	dummy.combat_stats.restore_poise()
	check(player.find_throw_target() == null, "Unbroken enemies cannot activate E")
	Input.action_press(&"special_attack")
	player.start_special_attack(1.0)
	player.set_input_frozen(true)
	Input.action_release(&"special_attack")
	check(not player.special_attack_charging and player.attack_state == player.AttackState.NONE, "Dialogue freeze discards a pending charge")
	player.set_input_frozen(false)
	player.start_special_attack(1.0)
	player.air_state = player.AirState.FALLING
	player.update_special_attack_charge(0.1)
	check(not player.special_attack_charging and player.attack_state == player.AttackState.NONE, "Losing the ground cancels charge without leaving a frozen attack")
	# Baked playback uses action seconds, including full hold and interrupted restart.
	var visual = player.heavy_charge_visual
	visual.advance(0.2, false, 0.0)
	visual.advance(1.0 / 60.0, true, 0.5)
	check(visual.frame == 27 and visual.visible, "Half charge selects the matching baked progress frame")
	visual.advance(1.0 / 60.0, true, 1.0)
	check(visual.frame == 54, "Full charge starts its flash exactly once")
	visual.advance(0.3, true, 1.0)
	check(visual.frame >= 70, "Full flash transitions to the baked hold loop")
	var before_loop: int = visual.frame
	visual.advance(0.7, true, 1.0)
	check(visual.frame == before_loop, "Full charge repeats the 42-frame hold loop")
	visual.advance(0.07, false, 0.0)
	check(visual.visible and is_equal_approx(visual.modulate.a, 0.5), "Interrupted or released charge fades on action time")
	visual.advance(0.01, true, 0.0)
	check(visual.frame == 0 and visual.modulate.a == 1.0, "A new charge clears the old fade and restarts")
	visual.advance(0.2, false, 0.0)
	var saved_frame: int = visual.frame
	visual.advance(0.0, true, 1.0)
	check(not visual.visible and visual.frame == saved_frame, "A stopped action clock does not advance or restart charge VFX")
	check(player.DODGE_ATTACK_1_SPEED == 600.0 and player.SLIDE_SPEED == 405.0, "Forward dodge attack and running slide receive modest speed increases")
	current_scene = null
	world.free()
	progress.free()
	root.add_child(original)
	Engine.time_scale = 1.0
	print("CHARGED HEAVY CHECKS: %d; failures: %d" % [checks, failures])
	quit(1 if failures else 0)
