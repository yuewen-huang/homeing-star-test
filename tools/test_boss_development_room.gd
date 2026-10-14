extends SceneTree

var room
var checks := 0
var failures := 0
var visual_dir := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func key(code: int, physical := true, echo := false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = echo
	if physical: event.physical_keycode = code
	else: event.keycode = code
	room._unhandled_key_input(event)

func freeze_specimen() -> void:
	room.adapter.boss.set_process(false)
	room.adapter.boss.set_physics_process(false)
	if room.selected_boss == 0:
		(room.adapter.boss as DeerBoss).vfx.set_process(false)
	else:
		room.adapter.boss.get_node("CombatTimeline").set_process_internal(false)

func advance(seconds: float) -> void:
	for tick in ceili(seconds * 60):
		if room.selected_boss == 0:
			var deer := room.adapter.boss as DeerBoss
			deer._physics_process(1.0 / 60)
			deer.vfx._process(1.0 / 60)
		else:
			var master = room.adapter.boss
			master._process(1.0 / 60)
			if master.combat_timeline.is_playing(): master.combat_timeline.advance(1.0 / 60)
		room._physics_process(1.0 / 60)

func capture(name: String) -> void:
	if visual_dir.is_empty(): return
	room._process(0)
	room.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(visual_dir.path_join(name + ".png")) == OK, "Native capture: " + name)

func switch_to(index: int) -> void:
	room.boss_picker.item_selected.emit(index)
	await process_frame
	await process_frame
	freeze_specimen()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--visual-dir")
	if index >= 0:
		visual_dir = args[index + 1]
		DirAccess.make_dir_recursive_absolute(visual_dir)
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var save_before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	var original_speed := Engine.time_scale
	var save_shortcuts := root.get_node("SaveProgress").is_processing_unhandled_input()
	var inventory_shortcuts := root.get_node("InventoryScreen").is_processing_unhandled_input()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.player.set_physics_process(false)
	freeze_specimen()
	check(room.boss_picker.item_count == 8 and room.selected_boss == 0, "Eight bosses populate selector; deer is default")
	check(not root.get_node("SaveProgress").is_processing_unhandled_input(), "Clear-save shortcut disabled inside development room")
	check(not root.get_node("InventoryScreen").is_processing_unhandled_input(), "Inventory cannot change real loadout in development room")
	check(room.player.is_ability_locked(SaveProgressService.ABILITY_JUMP) == false, "Preview player has local ability permissions")
	check(room.player.is_invulnerable(), "Preview player is invulnerable")
	check(not room.player.can_accept_parry_action(), "Contact QTE disabled for visual preview")
	check(not room.player.get_node("SkillBar").visible, "Gameplay HUD does not cover the test stage")
	var deer := room.adapter.boss as DeerBoss
	check(deer.manual_control, "Deer uses opt-in manual AI mode")
	check(deer.get_node("Hurtbox").collision_layer == 0 and not deer.is_in_group(&"damageable"), "Player cannot accidentally defeat the specimen")
	check(not deer.mist.visible and not deer.mist.is_processing(), "Global fog disabled; skill effects remain visible")
	var at := deer.position
	advance(12)
	check(deer.state == DeerBoss.State.IDLE and deer.position == at and deer.attack_hitbox.attack == null, "Deer stays idle for twelve seconds without chasing or attacking")
	await capture("deer_idle")
	key(KEY_1)
	check(deer.state == DeerBoss.State.LIGHT, "Physical key 1 plays the real deer light attack")
	advance(0.3)
	await capture("deer_light_warning")
	var time := deer._time
	key(KEY_1, true, true)
	check(is_equal_approx(deer._time, time), "Held-key echo does not repeatedly restart attacks")
	room.player.position = deer.position + Vector2(-90, 0)
	advance(0.3)
	check(deer.attack_hitbox.attack != null and not painted("light_stomp").is_empty(), "Manual light attack runs its production hitbox and VFX")
	check(room.player.combat_stats.health == 100 and not root.get_node("ParryQTE").active, "Overlapping light attack cannot damage player or start QTE")
	await capture("deer_light_impact")
	key(KEY_1, false)
	check(deer.state == DeerBoss.State.LIGHT and is_zero_approx(deer._time) and painted("light_stomp").is_empty(), "Logical key fallback restarts cleanly from frame zero")
	advance(4)
	check(deer.state == DeerBoss.State.IDLE and deer.attack_hitbox.attack == null, "Light attack recovers to idle without auto chaining")
	key(KEY_KP_2)
	check(deer.state == DeerBoss.State.HEAVY, "Numpad 2 plays the real deer heavy attack")
	advance(1.0)
	await capture("deer_heavy_warning")
	advance(0.6)
	check(deer.vfx._waves.is_empty() and not painted("heavy_stomp").is_empty(), "Manual heavy attack generates the local PLUS stomp without waves")
	await capture("deer_heavy_impact")
	key(KEY_R)
	await process_frame
	await process_frame
	freeze_specimen()
	check(room.adapter.boss != deer and room.adapter.boss.position == Vector2(820, 555), "R respawns selected boss instead of preserving damaged state")
	check(room.player.position == Vector2(380, 555), "R restores player position")
	check((room.adapter.boss as DeerBoss).vfx._waves.is_empty(), "R removes existing wave effects")
	check(get_nodes_in_group(&"damageable").is_empty(), "Removed specimens leave no damageable nodes behind")
	await switch_to(1)
	var master = room.adapter.boss
	check(master.manual_control and room.selected_boss == 1, "Dropdown switches to the master manual adapter")
	at = master.position
	advance(12)
	check(master.state == master.State.CHASE and master.position == at and not master.combat_timeline.is_playing(), "Master remains idle without auto chasing or selecting attacks")
	await capture("master_idle")
	room.light_button.pressed.emit()
	check(master.combat_timeline.current_animation == &"attack_1", "Light button runs the master's production timeline")
	advance(0.2)
	await capture("master_light")
	key(KEY_2)
	check(master.combat_timeline.current_animation == &"attack_2" and is_zero_approx(master.combat_timeline.current_animation_position), "Key 2 interrupts and restarts as master heavy attack")
	advance(0.3)
	await capture("master_heavy")
	room.show_hitboxes = true
	advance(0.55)
	check(master.attack_hitbox.attack != null, "Hitbox overlay capture uses an active production attack segment")
	check(not room.dummy.contacts.is_empty(), "Master production attack also reaches the shared wooden dummy")
	await capture("master_active_hitbox")
	room.show_hitboxes = false
	advance(5)
	check(not master.combat_timeline.is_playing() and master.attack_hitbox.attack == null and master.state == master.State.CHASE, "Master returns to manual idle after recovery")
	var phase := int(master.phase)
	key(KEY_F7)
	master._unhandled_key_input(InputEventKey.new())
	check(master.phase == phase, "Development preview cannot trigger the gameplay phase hotkey")
	for i in 6: await switch_to(i % 2)
	var specimens: Array = room.get_children().filter(func(child: Node) -> bool: return child.name == &"Specimen")
	check(specimens.size() == 1 and room.specimen.get_parent() == room, "Repeated selection keeps a single specimen subtree")
	# The player's own global bullet-time visual listens permanently; bosses must not pile up.
	var boss_listeners: Array = room.player.dodge_evaded_attack.get_connections().filter(func(c: Dictionary) -> bool: return not (c.callable.get_object() is DodgeBulletTimeVisual))
	check(boss_listeners.size() <= 1, "Boss switching does not accumulate player signal connections")
	room.speed_picker.item_selected.emit(0)
	check(is_equal_approx(Engine.time_scale, 0.25), "Speed selector applies quarter-speed simulation")
	room.show_hitboxes = true
	room.show_grid = false
	await capture("master_tools")
	current_scene = null
	room.free()
	await process_frame
	check(is_equal_approx(Engine.time_scale, original_speed), "Leaving room restores prior playback speed")
	check(root.get_node("SaveProgress").is_processing_unhandled_input() == save_shortcuts and root.get_node("InventoryScreen").is_processing_unhandled_input() == inventory_shortcuts, "Leaving room restores global shortcuts")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == save_before), "User save remains byte-identical")
	var ordinary_deer := DeerBoss.new()
	check(not ordinary_deer.manual_control, "Production deer AI mode is unchanged by default")
	ordinary_deer.free()
	var ordinary_master = load("res://scripts/sideview/tutorial_master_boss.gd").new()
	check(not ordinary_master.manual_control, "Production master AI mode is unchanged by default")
	ordinary_master.free()
	print("BOSS DEVELOPMENT ROOM: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func painted(kind: String) -> Array:
	return room.adapter.deer.vfx._painted.filter(func(effect: DeerPaintedEffect) -> bool: return effect.kind == kind)
