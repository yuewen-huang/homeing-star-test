extends SceneTree
## Input/movement regression for the once-per-airborne-trip dash budget.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var checks := 0
var failures := 0
var player: LanPlayer

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(count := 1) -> void:
	for i in count: player._physics_process(1.0 / 60)

func press_direction(action: StringName) -> void:
	Input.action_press(action)
	Input.action_press(&"instant_dash")
	tick()
	Input.action_release(action)
	Input.action_release(&"instant_dash")
	tick()

func take_off() -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	player.reset_after_map_fall(Vector2(0, 2000))
	player.start_jump()
	tick(14)

func finish_dash() -> void:
	for i in 40:
		if player.attack_state != LanPlayer.AttackState.AERIAL_DASH: break
		tick()

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	player = load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x = -5000
	player.world_max_x = 5000
	player.fallback_ground_y = 2000
	player.position = Vector2(0, 2000)
	world.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.start_aerial_dash(1)
	check(player.attack_state == LanPlayer.AttackState.NONE and not player.aerial_dash_used, "Grounded call cannot start or spend an aerial dash")
	take_off()
	var start_x := player.position.x
	press_direction(&"ui_right")
	check(player.attack_state == LanPlayer.AttackState.AERIAL_DASH and player.aerial_dash_used, "Airborne U press starts and spends the first dash")
	var elapsed := player.aerial_dash_elapsed
	var target := player.aerial_dash_target_x
	player.start_aerial_dash(-1)
	check(player.aerial_dash_elapsed == elapsed and player.aerial_dash_target_x == target, "Calling again during the dash cannot restart its clock or change direction")
	finish_dash()
	check(is_equal_approx(player.position.x - start_x, LanAerialDash.DISTANCE), "First dash retains its authored travel distance")
	check(player.air_state == LanPlayer.AirState.FALLING and player.aerial_dash_used, "Completing a dash restores falling without refilling the budget")
	var second_dash := false
	for action: StringName in [&"ui_left", &"ui_right", &"ui_left", &"ui_right"]:
		press_direction(action)
		second_dash = second_dash or player.attack_state == LanPlayer.AttackState.AERIAL_DASH
	check(not second_dash and player.velocity.y > 0 and player.position.y < 2000, "Alternating direction presses in the same flight cannot hover or dash again")
	player.start_double_jump()
	player.start_aerial_dash(1)
	check(player.double_jump_used and player.aerial_dash_used and player.attack_state != LanPlayer.AttackState.AERIAL_DASH, "Double jump does not restore the spent dash")
	player.air_state = LanPlayer.AirState.WALL_SLIDING
	player.wall_slide_normal_x = -1
	player.start_wall_jump()
	player.start_aerial_dash(-1)
	check(player.aerial_dash_used and player.attack_state != LanPlayer.AttackState.AERIAL_DASH, "Wall jump does not restore the spent dash")
	for i in 180:
		tick()
		if player.air_state == LanPlayer.AirState.GROUNDED: break
	check(player.position.y == 2000 and not player.aerial_dash_used, "Real ground contact restores the dash")
	if player.air_state == LanPlayer.AirState.ROLL_LANDING: player.finish_roll_landing()
	else: player.finish_landing()
	player.start_jump()
	tick(14)
	press_direction(&"ui_left")
	check(player.attack_state == LanPlayer.AttackState.AERIAL_DASH, "A new grounded jump can dash again")
	player.animated_sprite.play(&"fall")
	player.update_aerial_dash_phase(1.0 / 60)
	player.start_aerial_dash(1)
	check(player.attack_state == LanPlayer.AttackState.NONE and player.aerial_dash_used, "Interrupted dash remains spent until landing")
	player.reset_after_map_fall(Vector2(0, 2000))
	check(not player.aerial_dash_used and player.attack_state == LanPlayer.AttackState.NONE, "Respawn clears the spent dash")
	player.position.y = 1000
	player.air_state = LanPlayer.AirState.FALLING
	player.play_air_animation(&"fall")
	press_direction(&"ui_right")
	check(player.attack_state == LanPlayer.AttackState.AERIAL_DASH, "Falling from a ledge gets one available dash")
	finish_dash()
	player.ledge_climb_finish = Vector2(0, 2000)
	player.finish_ledge_climb()
	check(not player.aerial_dash_used, "Finishing a ledge climb onto a platform restores the dash")
	player.start_jump()
	tick(14)
	player.start_double_jump()
	player.start_aerial_dash(1)
	check(player.attack_state == LanPlayer.AttackState.AERIAL_DASH and player.aerial_dash_used, "Saving the dash for the second jump remains possible")
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	world.queue_free()
	await process_frame
	await process_frame
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "Regression preserves saved progress")
	print("AERIAL_DASH_LIMIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
