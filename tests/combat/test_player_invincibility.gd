extends SceneTree

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var failures := 0
var checks := 0
var room: Chapter1DeerBossRoom
var assist: BattleAssistSettingsService

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func reset_player() -> void:
	room.player.reset_after_map_fall(Vector2(600, 555))
	room.player.parry_chain.cancel()
	room.player.combat_stats.restore_health()
	room.player.velocity = Vector2.ZERO
func press(pressed := true, echo := false, keycode := KEY_F12) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.pressed = pressed
	key.echo = echo
	Input.parse_input_event(key)
	Input.flush_buffered_events()
func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	assist = root.get_node("BattleAssist") as BattleAssistSettingsService
	check(assist.player_invincible, "invincibility is enabled by default")
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	if is_instance_valid(room.story.comic):
		room.story._close_intro()
	await process_frame
	room.deer.set_physics_process(false)
	room.player.set_physics_process(false)
	room.deer.manual_control = true
	for danger in [CombatAttackData.DangerType.NORMAL, CombatAttackData.DangerType.COUNTERABLE_DANGER, CombatAttackData.DangerType.UNPARRYABLE_DANGER]:
		reset_player()
		var attack := CombatAttackData.new(&"practice_hit", room.deer, 20, 12, 180, -180, danger)
		check(room.player.receive_combat_hit(attack) == CombatHitResult.Type.NORMAL_HIT, "protected play resolves real danger type %d hits" % danger)
		check(room.player.combat_stats.health == room.player.combat_stats.max_health-20 and room.player.hit_reaction_active, "danger type %d removes HP and keeps the hit reaction" % danger)
	var deaths: Array=[]
	room.player.combat_stats.health_depleted.connect(func()->void:deaths.append(true))
	var lethal:=CombatAttackData.new(&"practice_lethal",room.deer,1000,12,180,0,CombatAttackData.DangerType.UNPARRYABLE_DANGER)
	for i in 3:
		reset_player()
		check(room.player.receive_combat_hit(lethal)==CombatHitResult.Type.NORMAL_HIT and room.player.combat_stats.health==room.player.combat_stats.max_health,"Lethal protected hit refills HP without skipping its response")
	check(deaths.is_empty(),"Auto-refill happens before any room death or restart signal")
	check(not room.deer.combat_stats.refill_health_on_depletion,"Player protection never makes the boss refill health")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	var normal := CombatAttackData.new(&"practice_normal", room.deer, 20, 12, 180, 0)
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.PARRY_FAILURE and room.player.combat_stats.health == room.player.combat_stats.max_health-10, "protected play keeps the ordinary guard half-damage rule")
	room.player.combat_stats.health=5
	room.player.defense_state=LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	check(room.player.receive_combat_hit(normal)==CombatHitResult.Type.PARRY_FAILURE and room.player.combat_stats.health==room.player.combat_stats.max_health,"Lethal ordinary guard damage also refills HP")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.PARRY_SUCCESS and room.player.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS, "ordinary parry still succeeds during invincibility")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var red := CombatAttackData.new(&"practice_red", room.deer, 20, 12, 180, 0, CombatAttackData.DangerType.COUNTERABLE_DANGER)
	check(room.player.receive_combat_hit(red) == CombatHitResult.Type.PARRY_SUCCESS and room.player.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "red counter still succeeds during invincibility")
	reset_player()
	press(true, false, KEY_F9)
	check(assist.player_invincible, "editor's F9 pause shortcut is no longer an invincibility binding")
	press(false); press(true, true)
	check(assist.player_invincible, "release and held-key repeat do not toggle invincibility")
	press()
	check(not assist.player_invincible and assist._invincibility_label.text == "F12 开启无敌", "F12 disables protection and updates the HUD through viewport input")
	check(not room.player.combat_stats.refill_health_on_depletion,"F12 immediately restores normal death rules")
	var physics_before := Engine.get_physics_frames()
	await physics_frame; await physics_frame
	check(not paused and Engine.get_physics_frames() > physics_before, "physics keeps advancing after disabling protection")
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.NORMAL_HIT and room.player.combat_stats.health == room.player.combat_stats.max_health - 20, "normal damage returns after turning protection off")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	room.player.receive_combat_hit(normal)
	check(room.player.combat_stats.health == room.player.combat_stats.max_health - 10, "ordinary guard retains the existing half-damage rule with protection off")
	root.get_tree().paused = true
	press()
	check(assist.player_invincible and assist.process_mode == Node.PROCESS_MODE_ALWAYS, "F12 protection remains accessible while paused")
	check(room.player.combat_stats.refill_health_on_depletion and assist._invincibility_label.text.contains("空血回满"),"Re-enabled protection updates refill behavior and its HUD explanation")
	root.get_tree().paused = false
	reset_player()
	room.player.combat_stats.apply_health_damage(1000)
	check(room.player.combat_stats.health==room.player.combat_stats.max_health and deaths.is_empty(),"Direct scripted player damage also refills before death signals")
	var ordinary_stats:=CombatantStats.new()
	root.add_child(ordinary_stats)
	ordinary_stats.apply_health_damage(ordinary_stats.max_health)
	check(ordinary_stats.health==0,"Unprotected combatant stats retain ordinary lethal damage")
	ordinary_stats.free()
	room.deer.reset_phase()
	check(assist.player_invincible, "encounter restart preserves the session's protection setting")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "protection toggle does not change story progress")
	room.queue_free()
	await process_frame; await process_frame
	print("PLAYER_INVINCIBILITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
