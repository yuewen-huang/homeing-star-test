extends SceneTree

class MemorySave extends SaveProgressService:
	var locked := false
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return not locked

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
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK, "Capture "+label)
func run() -> void:
	var old := root.get_node("SaveProgress"); root.remove_child(old); old.free()
	var save := MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field); current_scene = field; field.set_physics_process(false)
	await process_frame; await process_frame
	lan = field.pawn.player
	var bar = lan.get_node("SkillBar")
	check(bar.visible and bar.slot_nodes[&"instant_dash"].visible and bar.slot_nodes[&"special_attack"].visible,
		"Shared skill and inventory slots are visible")
	check(not bar.slot_nodes[&"jump"].visible, "Planar exploration hides the inactive jump slot")
	save.abilities_changed.emit()
	check(not bar.slot_nodes[&"jump"].visible, "Unlock refresh preserves planar jump restriction")
	field.feet = Chapter2SaltField.RETURN_POINT; field._sync_view(0)
	check(field.return_gate.get_child(0) is CommonPortalVisual and field.return_prompt.can_interact(), "Shared portal art and nearby E prompt replace prototype rectangle")
	await capture("salt_shared_portal_ui")
	field.feet = Vector2(1200,1500); field._sync_view(0)
	lan.facing_direction = 1
	var before := field.feet
	key(KEY_U)
	check(lan.attack_state == LanPlayer.AttackState.INSTANT_DASH and lan.position == Vector2.ZERO,
		"U starts authored instant dash without vertical snapping")
	await frames(50)
	check(is_equal_approx(field.feet.x - before.x, LanPlayer.INSTANT_DASH_DISTANCE) and field.feet.y == before.y,
		"Instant dash moves logical feet horizontally by the shared distance")
	check(lan.instant_dash_cooldown_remaining > 0 and bar.cooldown_overlays[&"instant_dash"].visible,
		"Shared cooldown is visible and advancing")
	before = field.feet; key(KEY_U); await frames(5)
	check(field.feet == before and field.pawn.can_move(), "Cooldown rejects repeated U without locking movement")
	Input.action_press(&"special_attack")
	key(KEY_I)
	await frames(50)
	check(lan.special_attack_charging and lan.special_attack_charge_elapsed > 0.7,
		"Holding I accumulates real charge and holds the charge pose")
	await capture("salt_heavy_charge")
	before = field.feet
	Input.action_release(&"special_attack")
	await frames(1)
	check(not lan.special_attack_charging and lan.special_attack_charge_ratio > 0,
		"Releasing I commits charge to production heavy attack")
	await frames(100)
	check(field.feet.x > before.x and field.feet.y == before.y, "Heavy lunge moves planar feet along the shared curve")
	check(field.pawn.can_move() and lan.position == Vector2.ZERO, "Heavy attack finishes without a stuck state or child drift")
	key(KEY_O)
	check(lan.ultimate_armed and not field.pawn.can_move(), "First O arms the production ultimate and locks cast movement")
	key(KEY_O)
	check(lan.ultimate_active, "Second O starts the production ultimate")
	await frames(6)
	await capture("salt_ultimate_active")
	before = field.feet
	await frames(360)
	check(not lan.ultimate_active and field.pawn.can_move() and field.feet == before \
		and lan.position.is_equal_approx(Vector2.ZERO), "Ultimate completes and restores planar feet without gravity or drift")
	key(KEY_O); await frames(360)
	check(not lan.ultimate_armed and field.pawn.can_move(), "Unused ultimate confirmation expires without freezing controls")
	var pile := field.piles[0]
	pile.excavated = false
	var obstacle := pile.footprint().grow_individual(16,8,16,8)
	field.feet = Vector2(obstacle.position.x - 45, pile.ground_position.y)
	field._sync_view(0); lan.facing_direction = 1; lan.instant_dash_cooldown_remaining = 0
	key(KEY_U); await frames(50)
	check(field.feet.x <= obstacle.position.x and not obstacle.has_point(field.feet),
		"Instant dash uses swept collision and cannot tunnel through an intact heap")
	pile.excavated = true
	field.feet = Vector2(obstacle.position.x - 45, pile.ground_position.y)
	field._sync_view(0); lan.instant_dash_cooldown_remaining = 0
	key(KEY_U); await frames(50)
	check(field.feet.x > obstacle.end.x, "Excavated heaps release the dash route")
	field.feet = Vector2(7090,120); field._sync_view(0)
	lan.instant_dash_cooldown_remaining = 0
	key(KEY_U); await frames(50)
	check(field.feet.x <= 7160 and field.feet.y == 120 and lan.position.is_equal_approx(Vector2.ZERO),
		"Far-depth dash obeys map bounds and never snaps to side-view ground")
	check(field.baked_boundary != null, "Shared UI and portal integration retains the baked boundary cache")
	lan.instant_dash_cooldown_remaining = 0
	save.locked = true; save.abilities_changed.emit()
	key(KEY_U); key(KEY_I); key(KEY_O)
	check(lan.attack_state == LanPlayer.AttackState.NONE and not lan.ultimate_armed,
		"UIO respect saved ability locks")
	check(not bar.slot_nodes[&"instant_dash"].visible and not bar.slot_nodes[&"special_attack"].visible,
		"Skill bar agrees with saved ability locks")
	bar.set_planar_exploration(false); save.locked = false; save.abilities_changed.emit()
	check(bar.slot_nodes[&"jump"].visible, "Ordinary side-view skill bar retains jump display")
	field.free(); current_scene = null
	print("SALT FIELD SKILLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
