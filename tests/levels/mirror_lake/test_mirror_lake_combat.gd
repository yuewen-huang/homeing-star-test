extends SceneTree
## Real map/player input, interruption and scene-local permission regression.
class LocalProgress extends SaveProgressService:
	var allow_parry := true
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(ability: StringName) -> bool:
		return allow_parry or ability != ABILITY_PARRY

var checks := 0
var failures := 0
var scene: MirrorLake
var player: LanPlayer

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func switch_side() -> void:
	scene.advance_switch(MirrorLake.SWITCH_COOLDOWN + 0.1)
	check(scene.request_switch(), "Map accepts a ready side switch")

func reset_yin() -> void:
	if scene.side == MirrorLake.Side.YIN: switch_side()
	if scene.side == MirrorLake.Side.YANG: switch_side()
	player.position = Vector2(MirrorLake.SPAWN_X, MirrorLake.STAND_Y)
	player.air_state = LanPlayer.AirState.GROUNDED
	player.velocity = Vector2.ZERO
	player.input_direction = 0.0
	player.resync_held_input_state()

func run() -> void:
	Input.use_accumulated_input = false
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var progress := LocalProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	scene.set_process(false)
	player = scene.player as LanPlayer
	player.set_physics_process(false)
	await process_frame
	check(scene.side == MirrorLake.Side.YANG and not player.are_attacks_allowed() and player.are_parries_allowed(), "Default yang starts in parry-only mode")
	switch_side()
	check(not player.is_ability_locked(SaveProgressService.ABILITY_ATTACK), "Yin retains unlocked attacks")
	check(player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Entry yin disables K")
	key(KEY_K, true)
	player._physics_process(1.0 / 60.0)
	check(player.defense_state == LanPlayer.DefenseState.NONE, "Actual K input cannot start parry in yin")
	key(KEY_K, false)
	await process_frame
	key(KEY_J, true)
	player._physics_process(1.0 / 60.0)
	check(player.attack_state == LanPlayer.AttackState.ATTACK_1X, "Actual J starts an attack in yin")
	key(KEY_J, false)
	player.attack_queued = true
	player.attack_input_buffer_remaining = 0.3
	player.special_attack_input_buffer_remaining = 0.3
	switch_side()
	check(player.attack_state == LanPlayer.AttackState.NONE and not player.attack_queued, "Switch to yang immediately cancels the running combo")
	check(not player.has_buffered_attack() and not player.has_buffered_special_attack(), "Switch discards both attack buffers")
	check(not scene.controls_inverted(), "Entry still exempts only direction inversion")
	for ability in [SaveProgressService.ABILITY_ATTACK, SaveProgressService.ABILITY_AIR_ATTACK,
		SaveProgressService.ABILITY_SPECIAL, SaveProgressService.ABILITY_DASH, SaveProgressService.ABILITY_ULTIMATE]:
		check(player.is_ability_locked(ability), "Yang blocks ability: " + String(ability))
	for code in [KEY_J, KEY_I, KEY_H, KEY_CTRL, KEY_O, KEY_E]:
		key(code, true)
		player._physics_process(1.0 / 60.0)
		check(player.attack_state == LanPlayer.AttackState.NONE and not player.ultimate_armed,
			"Forbidden physical key cannot start an attack: " + str(code))
		key(code, false)
		player._physics_process(1.0 / 60.0)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	player._physics_process(1.0 / 60.0)
	check(player.attack_state == LanPlayer.AttackState.NONE, "Yang blocks left mouse attack")
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	for method in [&"start_attack_1x", &"start_attack_2x", &"start_attack_2x_1", &"start_attack_2x_2",
		&"start_attack_3x", &"start_jump_attack_1x", &"start_jump_attack_2x", &"start_dodge_attack_1x",
		&"start_dodge_attack_2x", &"start_dodge_attack_3x", &"start_special_attack", &"perform_special_attack",
		&"start_sword_wave", &"start_instant_dash", &"arm_ultimate", &"start_ultimate_combo"]:
		if method == &"perform_special_attack": player.call(method, 1.0)
		else: player.call(method)
		check(player.attack_state == LanPlayer.AttackState.NONE and not player.ultimate_active and not player.ultimate_armed,
			"Direct entry also obeys yang: " + String(method))
	progress.allow_parry = false
	check(not player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Yang grants K locally even without a saved unlock")
	key(KEY_K, true)
	player._physics_process(1.0 / 60.0)
	check(player.defense_state == LanPlayer.DefenseState.PARRY_ACTIVE, "Actual K starts parry in yang")
	key(KEY_K, false)
	await process_frame
	player.parry_input_buffer_remaining = 0.3
	switch_side()
	check(player.defense_state == LanPlayer.DefenseState.NONE and not player.has_buffered_parry(), "Yin revokes active/buffered parry immediately")
	progress.allow_parry = true
	# A charge release and a previously launched wave must not leak after switching.
	reset_yin()
	player.start_special_attack(1.0)
	check(player.special_attack_charging, "Yin heavy charge begins")
	switch_side()
	check(not player.special_attack_charging and player.timeline_attack_effect == null, "Yang cancels heavy charge before release")
	player.perform_special_attack(1.0, 1.0)
	check(player.attack_state == LanPlayer.AttackState.NONE, "Releasing the cancelled charge cannot commit damage")
	reset_yin()
	player.start_sword_wave(1.0)
	player.sword_wave_fx.on_frame(7)
	var wave: LanSwordWaveProjectile = player.sword_wave_fx.projectiles[0]
	check(is_instance_valid(wave), "Yin sword wave launches a real projectile")
	switch_side()
	check(wave.is_queued_for_deletion() and player.sword_wave_fx.projectiles.is_empty(), "Yang cancels already-launched sword waves")
	reset_yin()
	player.arm_ultimate()
	switch_side()
	check(not player.ultimate_armed and player.ground_action_state == LanPlayer.GroundActionState.NONE, "Yang cancels first-step ultimate casting")
	reset_yin()
	player.start_ultimate_combo()
	var at := player.global_position
	var layer := player.ultimate.ultimate_saved_collision_layer
	var z := player.ultimate.ultimate_saved_z_index
	switch_side()
	check(not player.ultimate_active and player.global_position == at, "Yang cancels an active ultimate without teleporting the player")
	check(player.collision_layer == layer and player.z_index == z and player.hurtbox.monitorable, "Ultimate cancellation restores collision, hurtbox and drawing layer")
	reset_yin()
	player.start_back_dodge(1.0)
	switch_side()
	check(player.ground_action_state == LanPlayer.GroundActionState.BACK_DODGE and player.combat_timeline.is_playing(), "Switching keeps the non-attacking L dodge timeline intact")
	for x in [5000.0, 10000.0, 14080.0]:
		player.position.x = x
		scene._update_zone_controls()
		check(not player.are_attacks_allowed() and player.are_parries_allowed(), "Yang permissions cover map x=" + str(x))
	var outside := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	outside.position = Vector2(0.0, 555.0)
	outside.world_min_x = -1000.0
	outside.world_max_x = 1000.0
	root.add_child(outside)
	outside.set_physics_process(false)
	check(outside.are_attacks_allowed() and outside.are_parries_allowed(), "Another map's player retains normal permissions")
	progress.allow_parry = false
	player.set_map_combat_mode(LanPlayer.MapCombatMode.DEFAULT)
	check(player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Removing the local rule restores the saved K lock")
	outside.queue_free()
	scene.queue_free()
	await process_frame
	root.remove_child(progress)
	progress.free()
	root.add_child(original)
	print("Mirror lake combat: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
