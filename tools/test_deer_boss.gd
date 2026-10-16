extends SceneTree

class TestProgress extends SaveProgressService:
	var vine_owned := true
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true
	func get_item_count(item_id: StringName) -> int:
		return 1 if item_id == ItemCatalog.VINE_SNARE and vine_owned else 0

var failures := 0
var checks := 0
var room: Chapter1DeerBossRoom
var boss: DeerBoss
var player: LanPlayer
var progress: TestProgress
var completion_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func advance(seconds: float) -> void:
	for i in ceili(seconds * 60):
		boss._physics_process(1.0 / 60)
		boss.vfx._process(1.0 / 60)
		room.mist_field._process(1.0 / 60)

func reset() -> void:
	Engine.time_scale = 1
	player.reset_after_map_fall(Vector2(1150, 555))
	player.combat_stats.restore_health()
	player.combat_stats.restore_poise()
	player.input_frozen = false
	player.boss_controlled = false
	player.ultimate_active = false
	player.dodge_bullet_time_remaining = 0
	boss.reset_phase()
	boss.position = Vector2(1000, 555)
	boss.set_physics_process(false)
	progress.vine_owned = true
	room.refresh_context_item()

func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--visual-dir")
	if index < 0: return
	var output := args[index + 1]
	DirAccess.make_dir_recursive_absolute(output)
	boss._update_cloak()
	boss.vfx.queue_redraw()
	room.mist_field.update_material()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	var had_save := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if had_save else PackedByteArray()
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	progress = TestProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate() as Chapter1DeerBossRoom
	root.add_child(room)
	current_scene = room
	boss = room.deer
	player = room.player
	boss.set_physics_process(false)
	player.set_physics_process(false)
	room.mist_field.set_process(false)
	await process_frame
	boss.vfx.set_process(false)
	boss.phase_completed.connect(func(_phase: int) -> void: completion_count += 1)
	reset()
	check(boss.combat_stats.health == 300 and boss.combat_stats.poise == 120, "Mist phase starts with 300 HP and 120 poise")
	check(DeerActionLibrary.clip(&"death_START").count + DeerActionLibrary.clip(&"death_ING").count + DeerActionLibrary.clip(&"death_END").count == 12 and DeerActionLibrary.clip(&"death_END").source_last == 11 and DeerActionLibrary.clip(&"getup_END").count == 1, "Physical death clips exclude rising frames, preserved as separate getup")
	check(boss.vfx._wave_frames.size() == 20, "Mist wave has twenty procedurally shaded animation frames")
	check(boss.vfx._wave_frames[0] == DeerMistArt.wave_frames()[0], "Procedural wave atlas is reused across room instances")
	var mist_image := boss.vfx._wave_frames[0].get_image()
	var occupied := 0
	var mist_colors: Dictionary = {}
	for y in mist_image.get_height():
		for x in mist_image.get_width():
			var color := mist_image.get_pixel(x, y)
			if color.a > 0.3:
				occupied += 1
				mist_colors[color.to_html()] = true
	check(occupied > 1000 and mist_colors.size() > 12, "Mist wave is a shaded filled volume, not disconnected marks")
	await capture("deer_idle")

	boss.receive_hit(1, player.position)
	check(boss.combat_stats.health == 292 and boss.combat_stats.poise == 110, "Normal player hit settles 8 health and 10 poise")
	boss.receive_skill_hit(SkillHitContext.new(&"normal_special", 18), player.position)
	check(boss.combat_stats.health == 274 and boss.state == DeerBoss.State.RECOVER, "Normal special interrupts an ordinary action")
	reset()
	for i in 12: boss.receive_hit(1, player.position)
	check(boss.state == DeerBoss.State.STAGGER and is_equal_approx(boss.stagger_remaining, 3.0), "Poise break opens a three-second window")
	boss.receive_skill_hit(SkillHitContext.new(&"max_special", 60, false, false, false, true), player.position)
	check(boss.combat_stats.health == 144 and is_equal_approx(boss.stagger_remaining, 3.0), "MAX deals 60 without shortening the break window")
	advance(3.1)
	check(not boss.poise_broken, "Poise break ends after its window")
	boss._phase_age = 0
	advance(5.0)
	check(boss.combat_stats.poise == 120, "Poise refills over five seconds after stagger")

	reset()
	boss.combat_stats.set_health_ratio(0.5)
	boss._phase_age = 7.9
	check(not boss.can_start_hunt(), "Half HP does not bypass the eight-second grace period")
	boss._phase_age = 8
	check(boss.can_start_hunt(), "Half HP schedules the first mist hunt")
	boss._physics_process(0.01)
	check(boss.state == DeerBoss.State.CHANT and room.mist_field.hunting, "AI enters the chant and thickens the fog")
	await capture("deer_chant")
	advance(1.25)
	check(boss.state == DeerBoss.State.HUNT_WARNING and boss._hunt_round == 1, "First ambush has a warning before movement")
	check(boss.animated_sprite.modulate.a == 0, "Ambusher is invisible outside the clear area")
	check(boss.vfx.warning_audio.stream != null, "Ambush supplies positional audio")
	await capture("deer_hidden_warning")
	advance(0.9)
	check(boss.state == DeerBoss.State.HUNT_CHARGE and boss.attack_hitbox.attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER, "Mist ambush is gold and cannot offer a parry")
	check(boss.use_vine_snare(), "Q catches a charging deer during the warning-to-contact window")
	check(boss.state == DeerBoss.State.STAGGER and boss.snared and is_equal_approx(boss.stagger_remaining, 4.5), "Snare reveals the deer for a 4.5-second output window")
	check(not room.mist_field.hunting and boss.vfx._waves.is_empty() and boss.attack_hitbox.attack == null, "Snare clears hunt, waves and hitboxes")
	check(not boss.use_vine_snare(), "One hunt cannot be countered twice")
	advance(0.5)
	check(room.mist_field.clear_radius > 190 and room.mist_field.density < 0.78, "Snare opens the fog for its output window")
	await capture("deer_snared")
	check(is_instance_valid(boss.vfx._painted_vine) and boss.vfx._painted_vine.front.visible and DeerPaintedArt.clip("vine_cage").frames.size() == 9, "Snare animates the nine supplied painted cage frames")
	advance(4.1)
	check(not boss.poise_broken and not boss.snared, "Snare releases after the entire window")
	advance(0.4)
	check(is_zero_approx(boss.vfx._snare_opacity) and not is_instance_valid(boss.vfx._painted_vine), "Front and back vines both fade out after release")
	check(not boss.can_start_hunt(), "Repeated hunt waits for cooldown")

	reset()
	boss.start_mist_hunt()
	progress.vine_owned = false
	room.refresh_context_item()
	check(not boss.use_vine_snare() and is_zero_approx(boss.item_cooldown), "Missing item never produces a counter or cooldown")
	check(player.get_node("SkillBar")._context_label.text == "?", "Missing item is shown in the contextual Q slot")
	progress.vine_owned = true
	check(not boss.use_vine_snare() and boss.item_cooldown == 4, "Premature Q misses and begins four-second cooldown")
	advance(1.25)
	check(not boss.use_vine_snare(), "Cooldown blocks immediate retry even in a valid window")
	player.position.y = 330
	advance(3.0)
	check(is_zero_approx(boss.item_cooldown), "Missed Q becomes available again in the same hunt")
	check(boss._hunt_active and boss.use_vine_snare(), "Retry can counter a later ambush")

	reset()
	player.position.y = 330
	progress.vine_owned = false
	boss.start_mist_hunt()
	advance(10.9)
	check(boss._hunt_round == 5 and not boss._hunt_active and boss.state == DeerBoss.State.RECOVER, "Four gold ambushes end with a heavy stomp and ordinary recovery")
	check(not boss.poise_broken and is_equal_approx(boss._recovery, 1.5), "Surviving without an item does not grant stagger")
	check(not boss.can_start_hunt(), "Completed hunt observes its 25-second interval")
	boss._phase_age = 30
	boss._hunt_cooldown = 0
	boss.combat_stats.set_health_ratio(0.5)
	check(boss.can_start_hunt(), "Hunt can repeat after the interval")

	reset()
	player.position = Vector2(1100, 555)
	boss.start_attack(DeerBoss.State.LIGHT)
	advance(0.49)
	check(player.combat_stats.health == 100, "Hoof does not hurt during its windup")
	advance(0.2)
	check(player.combat_stats.health == 88, "Hoof deals 12 once on its landing frames")
	advance(0.2)
	check(player.combat_stats.health == 88, "A single hoof segment cannot deal repeated contact damage")

	reset()
	player.position = Vector2(1100, 555)
	boss.start_attack(DeerBoss.State.HEAVY)
	advance(0.95)
	await capture("deer_red_warning")
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	advance(0.5)
	check(boss.state == DeerBoss.State.STAGGER and is_equal_approx(boss.stagger_remaining, 2.0), "Red parry interrupts the stomp into two-second stagger")
	check(player.combat_stats.health == 100 and boss.vfx._waves.is_empty() and boss.attack_hitbox.attack == null, "Red counter prevents stomp damage and closes the PLUS hitbox")
	player.red_parry_finished.emit(boss)
	player.defense_state = LanPlayer.DefenseState.NONE

	reset()
	player.position = Vector2(1150, 555)
	boss.start_attack(DeerBoss.State.CHARGE)
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	check(is_equal_approx(boss.position.x, 1000), "Close-range charge no longer teleports the boss")
	advance(1.04)
	check(player.combat_stats.health == 82 and not boss.poise_broken, "K cannot parry a gold charge")
	player.defense_state = LanPlayer.DefenseState.NONE
	advance(0.25)
	check(player.combat_stats.health == 60 and player.velocity.y < 0, "Follow-up uppercut turns toward the target and launches for 22 damage")

	reset()
	player.position = Vector2(1100, 555)
	player.start_back_dodge(-1)
	boss.open_attack(&"dodge_case", Rect2(0, -120, 180, 120), 18, CombatAttackData.DangerType.UNPARRYABLE_DANGER)
	boss.resolve_attack_contact()
	check(player.combat_stats.health == 100 and is_equal_approx(boss.get_action_time_scale(), 0.18), "Successful dodge triggers boss action slow motion")
	var earlier := boss._time
	boss._physics_process(0.1)
	check(boss._time - earlier < 0.03, "Body timeline follows action slow motion")

	reset()
	boss.start_attack(DeerBoss.State.HEAVY)
	player.position = Vector2(1250, 555)
	advance(1.7)
	check(boss.vfx._waves.is_empty() and boss.vfx._painted.any(func(effect: DeerPaintedEffect) -> bool: return effect.kind == "heavy_stomp" and effect.back.visible), "Uncountered stomp preserves the supplied rear painted impact at 1.7 seconds without ground-wave damage")
	await capture("deer_heavy_plus")
	room.restart_mist_phase()
	boss.set_physics_process(false)
	check(boss.combat_stats.health == 300 and player.combat_stats.health == 100 and boss.vfx._waves.is_empty(), "Death retry restores phase HP and clears residual attacks")
	check(not room.mist_field.hunting, "Retry restores ordinary fog")
	check(boss.vfx.heavy_dust_bursts().is_empty() and boss.vfx._light_impacts.is_empty() and not is_instance_valid(boss.vfx._painted_vine) and is_zero_approx(boss.vfx._snare_opacity), "Retry clears impact clouds and both snare layers")

	reset()
	player.position = Vector2(910, 555)
	player.facing_direction = 1
	player.apply_facing_direction()
	boss._recover(100)
	player.set_physics_process(true)
	var attack_key := InputEventKey.new()
	attack_key.physical_keycode = KEY_J
	attack_key.keycode = KEY_J
	attack_key.pressed = true
	Input.parse_input_event(attack_key)
	for i in 3: await physics_frame
	attack_key = InputEventKey.new()
	attack_key.physical_keycode = KEY_J
	attack_key.keycode = KEY_J
	Input.parse_input_event(attack_key)
	for i in 120: await physics_frame
	player.set_physics_process(false)
	check(boss.combat_stats.health < 300, "Real J input and player attack effects can hit the deer hurtbox")
	reset()
	boss.start_mist_hunt()
	boss._start_hunt_round()
	player.set_physics_process(true)
	var item_key := InputEventKey.new()
	item_key.physical_keycode = KEY_Q
	item_key.keycode = KEY_Q
	item_key.pressed = true
	Input.parse_input_event(item_key)
	for i in 3: await physics_frame
	item_key = InputEventKey.new()
	item_key.physical_keycode = KEY_Q
	item_key.keycode = KEY_Q
	Input.parse_input_event(item_key)
	player.set_physics_process(false)
	check(boss.snared and boss.state == DeerBoss.State.STAGGER, "Real Q input uses the contextual snare without equipping it")
	check(progress.get_equipped_special_item() == &"", "Contextual Q leaves the saved loadout unchanged")

	reset()
	var avoids_repeat := true
	for i in 200:
		boss._choose_attack(180)
		avoids_repeat = avoids_repeat and boss._repeat_count <= 2
	check(avoids_repeat, "AI avoids three identical consecutive attacks across 200 choices")
	reset()
	boss.receive_skill_hit(SkillHitContext.new(&"end_phase", 300), player.position)
	check(boss.state == DeerBoss.State.PHASE_END and boss.invulnerable, "Empty phase HP starts protected fall/getup/howl transition")
	boss.receive_hit(1, player.position)
	advance(boss.phase_transition.duration(DeerPhaseTransition.FALL) + boss.phase_transition.duration(DeerPhaseTransition.RISE) + DeerPhaseTransition.ROAR_DURATION + 0.05)
	check(boss.state == DeerBoss.State.IDLE and completion_count == 1 and boss.phase == 2, "Mist completion resumes the integrated root phase after the full handoff")
	await capture("deer_phase_complete")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == had_save and (not had_save or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before), "Test and phase completion leave the user's save untouched")
	print("DEER TESTS: ", checks, " checks; ", failures, " failures")
	room.queue_free()
	await process_frame
	(root.get_node("CombatFeedback") as CombatFeedbackService).impact_player.stop()
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_player.stop()
	(root.get_node("SceneTransition") as SceneTransitionService).music_player.stop()
	OS.delay_msec(100)
	quit(1 if failures else 0)
