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
var settings: AudioSettingsService
const Modes := BattleAssistSettingsService.Difficulty

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
func press(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	root.push_input(key)
	var release := key.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release)

func choose(mode: int) -> void:
	var picker := settings.difficulty_picker
	picker.get_popup().index_pressed.emit(picker.get_item_index(mode))

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	assist = root.get_node("BattleAssist") as BattleAssistSettingsService
	settings = root.get_node("AudioSettings") as AudioSettingsService
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		push_error("Run this test through run-tests.ps1 for isolated settings")
		quit(2)
		return
	settings.settings_path = output.path_join("easy-mode-settings.cfg")
	assist.set_difficulty(Modes.EASY)
	check(not assist._lives_label.visible, "easy shows no HUD text before a boss attempt")
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	var title = load("res://scenes/ui/title_menu.tscn").instantiate()
	root.add_child(title); current_scene = title
	await process_frame
	title.menu_buttons[2].grab_focus()
	press(KEY_ENTER)
	check(paused and settings.settings_panel.visible and settings.difficulty_picker.has_focus(), "title settings opens and focuses the difficulty picker")
	choose(Modes.HARD)
	check(assist.difficulty == Modes.HARD and not assist.player_invincible, "title difficulty takes effect before entering the game")
	choose(Modes.EASY)
	await capture("easy_title_settings")
	press(KEY_ESCAPE)
	check(not paused and title.menu_buttons[2].has_focus(), "closing settings restores title focus")
	title.free()
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	if is_instance_valid(room.story.comic):
		room.story._close_intro()
	await process_frame
	room.deer.set_physics_process(false)
	room.player.set_physics_process(false)
	room.deer.manual_control = true
	check(assist._lives_label.visible and assist._lives_label.text.contains("1 条命"), "a new easy-mode boss starts on the first life")
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
	check(assist.boss_refill_count == 3 and assist._lives_label.text == "自动回血 3 次 · 用了 4 条命", "each lethal refill adds one life")
	await capture("easy_boss_lives")
	check(not room.deer.combat_stats.refill_health_on_depletion,"Player protection never makes the boss refill health")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	var normal := CombatAttackData.new(&"practice_normal", room.deer, 20, 12, 180, 0)
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.PARRY_FAILURE and room.player.combat_stats.health == room.player.combat_stats.max_health-10, "protected play keeps the ordinary guard half-damage rule")
	room.player.combat_stats.health=5
	room.player.defense_state=LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	check(room.player.receive_combat_hit(normal)==CombatHitResult.Type.PARRY_FAILURE and room.player.combat_stats.health==room.player.combat_stats.max_health,"Lethal ordinary guard damage also refills HP")
	check(assist.boss_refill_count == 4, "lethal guard damage counts; manual health restoration does not")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.PARRY_SUCCESS and room.player.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS, "ordinary parry still succeeds during invincibility")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var red := CombatAttackData.new(&"practice_red", room.deer, 20, 12, 180, 0, CombatAttackData.DangerType.COUNTERABLE_DANGER)
	check(room.player.receive_combat_hit(red) == CombatHitResult.Type.PARRY_SUCCESS and room.player.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "red counter still succeeds during invincibility")
	reset_player()
	press(KEY_F11)
	press(KEY_F12)
	check(assist.difficulty == Modes.EASY and assist.player_invincible, "old function keys do not change the menu selection")
	press(KEY_ESCAPE)
	check(paused and settings.settings_panel.visible, "ESC opens the same settings in the boss room")
	choose(Modes.NORMAL)
	check(not room.player.combat_stats.refill_health_on_depletion and not assist._lives_label.visible, "normal immediately restores death rules and hides the counter")
	press(KEY_ESCAPE)
	var physics_before := Engine.get_physics_frames()
	await physics_frame; await physics_frame
	check(not paused and Engine.get_physics_frames() > physics_before, "physics keeps advancing after disabling protection")
	check(room.player.receive_combat_hit(normal) == CombatHitResult.Type.NORMAL_HIT and room.player.combat_stats.health == room.player.combat_stats.max_health - 20, "normal damage returns after turning protection off")
	reset_player()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	room.player.receive_combat_hit(normal)
	check(room.player.combat_stats.health == room.player.combat_stats.max_health - 10, "ordinary guard retains the existing half-damage rule with protection off")
	press(KEY_ESCAPE)
	choose(Modes.EASY)
	check(room.player.combat_stats.refill_health_on_depletion and assist.boss_refill_count == 4, "re-enabling easy restores the same attempt's count")
	await capture("easy_pause_settings")
	press(KEY_ESCAPE)
	reset_player()
	room.player.combat_stats.apply_health_damage(1000)
	check(room.player.combat_stats.health==room.player.combat_stats.max_health and deaths.is_empty(),"Direct scripted player damage also refills before death signals")
	var ordinary_stats:=CombatantStats.new()
	root.add_child(ordinary_stats)
	ordinary_stats.apply_health_damage(ordinary_stats.max_health)
	check(ordinary_stats.health==0,"Unprotected combatant stats retain ordinary lethal damage")
	ordinary_stats.free()
	room.encounter._spawn_phase(2, room.encounter.arena_center)
	check(assist.boss_refill_count == 5, "replacing the deer actor at a phase handoff keeps the count")
	room.restart_mist_phase()
	check(assist.player_invincible and assist.boss_refill_count == 0, "restarting the encounter resets the count and keeps the setting")
	room.player.combat_stats.apply_health_damage(1000)
	assist.end_boss_attempt(room.encounter, true)
	room.player.combat_stats.apply_health_damage(1000)
	check(assist.boss_refill_count == 1 and assist._lives_label.visible, "victory displays a frozen result")
	assist.set_difficulty(Modes.HARD)
	settings._load_settings()
	check(assist.difficulty == Modes.EASY and settings.difficulty_picker.get_selected_id() == Modes.EASY, "selected difficulty reloads from settings")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "protection toggle does not change story progress")
	room.queue_free()
	await process_frame; await process_frame
	check(not assist._lives_label.visible and assist.boss_refill_count == 0, "leaving the room clears the result")
	print("PLAYER_INVINCIBILITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
