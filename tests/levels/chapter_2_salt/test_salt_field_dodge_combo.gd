extends SceneTree

class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var field: Chapter2SaltField
var lan: LanPlayer
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func frames(count: int) -> void:
	for i in count:
		field.step_exploration(1.0/60, Vector2.ZERO, false, false)
		await process_frame
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK, "Capture "+label)
func start_roll_attack() -> void:
	key(KEY_L)
	field.step_exploration(1.0/60, Vector2.ZERO, false, field._dodge_queued)
	field._dodge_queued = false
	for i in 120:
		if lan.back_dodge_attack_cancel_open: break
		await frames(1)
	key(KEY_J); await frames(1)
func run() -> void:
	var old := root.get_node("SaveProgress"); root.remove_child(old); old.free()
	var save := MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field); current_scene = field; field.set_physics_process(false)
	await process_frame; await process_frame
	lan = field.pawn.player
	for pile in field.piles: pile.excavated = true
	field.feet = Vector2(1800,1500); field._sync_view(0)
	lan.facing_direction = 1
	await start_roll_attack()
	check(lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_1X, "Actual L then J enters the production rolling attack")
	var before := field.feet
	await frames(6)
	check(field.feet.x > before.x and field.feet.y == before.y and field.dodge_remaining == 0,
		"Forward burst replaces reverse dodge motion without depth movement")
	await capture("salt_roll_attack_1")
	key(KEY_J)
	for i in 180:
		if lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_2X: break
		await frames(1)
	check(lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_2X, "Second J continues into authored rolling attack 2")
	key(KEY_J)
	var airborne := false
	for i in 180:
		if lan.position.y < -1: airborne = true
		if lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_3X: break
		await frames(1)
	check(airborne and field.feet.y == before.y, "Second strike launches visually while logical depth stays fixed")
	check(lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_3X, "Third J continues into the real finisher")
	for i in 120:
		if lan.dodge_attack_3_teleported: break
		await frames(1)
	check(lan.dodge_attack_3_teleported and lan.position.y < -100, "Finisher plays its overhead drop")
	await capture("salt_roll_finisher_drop")
	await frames(30)
	await capture("salt_roll_finisher_landing")
	await frames(180)
	check(field.pawn.can_move() and lan.air_state == LanPlayer.AirState.GROUNDED \
		and lan.position.is_equal_approx(Vector2.ZERO) and field.feet.y == before.y,
		"Full combo lands and releases movement without child drift or changed depth")
	# Stopping after the second hit must also land rather than leave the adapter in the air.
	field.dodge_cooldown = 0; lan.facing_direction = 1
	await start_roll_attack(); key(KEY_J)
	await frames(240)
	check(field.pawn.can_move() and lan.position == Vector2.ZERO and lan.air_state == LanPlayer.AirState.GROUNDED,
		"Two-hit route lands cleanly without requiring the third input")
	# Shared attack cancellation is part of the same missing combat route.
	key(KEY_J); await frames(3)
	key(KEY_K); await frames(1)
	check(lan.defense_state != LanPlayer.DefenseState.NONE and lan.attack_state == LanPlayer.AttackState.NONE,
		"K cancels a normal attack through the production parry rules")
	await frames(100)
	key(KEY_J); await frames(3)
	field.dodge_cooldown = 0
	key(KEY_L)
	field.step_exploration(1.0/60, Vector2.ZERO, false, field._dodge_queued)
	field._dodge_queued = false
	check(lan.ground_action_state == LanPlayer.GroundActionState.BACK_DODGE,
		"L cancels a normal attack through the production dodge rules")
	await frames(100)
	check(field.pawn.can_move(), "Canceled actions also restore movement")
	field.feet = Vector2(1800,300); field._sync_view(0)
	field.dodge_cooldown = 0; lan.facing_direction = 1
	key(KEY_L); key(KEY_J)
	field.step_exploration(1.0/60, Vector2.ZERO, false, field._dodge_queued)
	field._dodge_queued = false
	for i in 120:
		if lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_1X: break
		await frames(1)
	check(lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_1X,
		"L and J in the same physics tick buffer into a rolling attack")
	key(KEY_J)
	for i in 120:
		if lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_2X: break
		await frames(1)
	key(KEY_J)
	for i in 180:
		if lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_3X: break
		await frames(1)
	var finisher_start := field.feet
	await frames(240)
	check(is_equal_approx(field.feet.x - finisher_start.x, LanPlayer.DODGE_ATTACK_3_FALLBACK_DISTANCE),
		"Finisher displacement retains logical distance at far depth")
	check(field.feet.y == 300 and lan.position.is_equal_approx(Vector2.ZERO) and field.pawn.can_move(),
		"Far-depth full combo preserves depth and lands without drift")
	field.free(); current_scene = null
	print("SALT FIELD DODGE COMBO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
