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
	room.player.combat_stats.restore_health()
	room.player.velocity = Vector2.ZERO
func press(pressed := true, echo := false) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F9
	key.pressed = pressed
	key.echo = echo
	assist._input(key)
func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	assist = root.get_node("BattleAssist") as BattleAssistSettingsService
	check(assist.player_invincible, "invincibility is enabled by default")
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.deer.set_physics_process(false)
	room.player.set_physics_process(false)
	room.deer.manual_control = true
	for danger in [CombatAttackData.DangerType.NORMAL, CombatAttackData.DangerType.COUNTERABLE_DANGER, CombatAttackData.DangerType.UNPARRYABLE_DANGER]:
		reset_player()
		var attack := CombatAttackData.new(&"practice_hit", room.deer, 20, 12, 180, -180, danger)
		check(room.player.receive_combat_hit(attack) == CombatHitResult.Type.EVADED, "invincibility blocks danger type %d" % danger)
		check(room.player.combat_stats.health == room.player.combat_stats.max_health and room.player.velocity == Vector2.ZERO, "danger type %d cannot remove HP or knock the player away" % danger)
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	var normal := CombatAttackData.new(&"practice_normal", room.deer, 20, 12, 180, 0)
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.EVADED and room.player.combat_stats.health == room.player.combat_stats.max_health, "failed/ordinary guard stays harmless during invincibility")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.PARRY_SUCCESS and room.player.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS, "ordinary parry still succeeds during invincibility")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var red := CombatAttackData.new(&"practice_red", room.deer, 20, 12, 180, 0, CombatAttackData.DangerType.COUNTERABLE_DANGER)
	check(room.player.receive_combat_hit(red) == CombatHitResult.Type.PARRY_SUCCESS and room.player.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "red counter still succeeds during invincibility")
	reset_player()
	press(false); press(true, true)
	check(assist.player_invincible, "release and held-key repeat do not toggle invincibility")
	press()
	check(not assist.player_invincible and assist._invincibility_label.text == "F9 开启无敌", "F9 disables protection and updates the HUD")
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.NORMAL_HIT and room.player.combat_stats.health == room.player.combat_stats.max_health - 20, "normal damage returns after turning protection off")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	room.player.receive_combat_hit(normal)
	check(room.player.combat_stats.health == room.player.combat_stats.max_health - 10, "ordinary guard retains the existing half-damage rule with protection off")
	root.get_tree().paused = true
	press()
	check(assist.player_invincible and assist.process_mode == Node.PROCESS_MODE_ALWAYS, "F9 protection remains accessible while paused")
	root.get_tree().paused = false
	room.deer.reset_phase()
	check(assist.player_invincible, "encounter restart preserves the session's protection setting")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "protection toggle does not change story progress")
	room.queue_free()
	await process_frame; await process_frame
	print("PLAYER_INVINCIBILITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
