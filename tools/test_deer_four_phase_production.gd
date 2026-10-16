extends SceneTree

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

class SkillHit extends RefCounted:
	var damage := 32

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var player: LanPlayer
var vine: DeerVinePhase
var assist: BattleAssistSettingsService
var checks := 0
var failures := 0
var completed: Array[int] = []
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func capture(name: String) -> void:
	if output.is_empty(): return
	# Manual ticks cover seconds of gameplay within one render frame; clear
	# the real-time hit flash so these captures show the current authored pose.
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.clear_body_reaction(boss.animated_sprite)
	feedback.screen_fx.clear()
	feedback._reset_punch()
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func tick(count: int, speed := 1.0) -> void:
	for i in count:
		boss._physics_process(speed / 60.0)
		boss.vfx._process(speed / 60.0)
func until(predicate: Callable, limit := 1200) -> bool:
	for i in limit:
		if predicate.call(): return true
		tick(1)
	return bool(predicate.call())
func reset_player() -> void:
	player.reset_after_map_fall(Vector2(1250, 555))
	player.combat_stats.restore_health()
	player.velocity = Vector2.ZERO
func reset_vine() -> void:
	# This helper explicitly starts a fresh in-memory fight, including after victory.
	if room.story._settled:
		room.story._settled = false
		room.story.victory_pending = false
		room._save._config.set_value("progress", String(SaveProgressService.STORY_C1_DEER_DEFEATED), false)
	assist.set_player_invincible(true)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	reset_player()
	boss.phase = 4
	boss.reset_phase()
	boss.set_physics_process(false)
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "production transform reaches the hovering human form")
	# Manual simulation must synchronize the real phase-four view before screen-sized casts.
	room._process(0)
	(room.get_node("Camera2D") as Camera2D).force_update_scroll()
## A vine at full reach over the player on its first active frame.
func contact(kind: StringName) -> DeerVineStrike:
	var from := player.global_position + Vector2(-300, -250)
	var strike := vine.spawn_strike(kind, player.position.x, player.position.x - 300.0, 0.0, from)
	# Step until the vine first reaches the player (a wiper reaches late in its sweep).
	for i in 120:
		strike.step(1.0 / 60)
		if strike.finished or strike.snapped or strike.hitbox.hit_targets.has(player.get_instance_id()): break
	return strike
func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	assist = root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	# This suite validates production combat after the independently tested intro.
	if room.story.comic != null: room.story.comic._request_finish(true)
	await process_frame; await process_frame
	boss = room.deer; player = room.player; vine = boss.vine_phase
	boss.set_physics_process(false); boss.vfx.set_process(false); player.set_physics_process(false)
	boss.phase_completed.connect(func(phase: int) -> void: completed.append(phase))
	check(boss.auto_advance_phases and boss.playable_phase_count == 4 and not boss.manual_control, "real final room enables all four production phases")
	var music := root.get_node("SceneTransition") as SceneTransitionService
	check(music.current_music_path == Chapter1Music.FINAL_BOSS.resource_path and music.music_player.playing and (music.music_player.stream as AudioStreamMP3).loop, "deer entry loops Forest BOSS 1 for phase one")
	check(Chapter1Music.FINAL_BOSS.get_length() > 0 and Chapter1Music.FINAL_BOSS_VINE.get_length() > 0, "both supplied forest boss MP3s decode with valid duration")
	music.music_player.seek(12.0)
	var first_stream := music.music_player.stream
	var nodule := boss.root_phase.add_nodule(Vector2(2000, 555))
	nodule._register_support()
	for phase in [1, 2, 3]:
		reset_player()
		boss.combat_stats.apply_health_damage(boss.combat_stats.health)
		check(boss.state == DeerBoss.State.PHASE_END and boss.phase_transition.to_phase == phase + 1, "phase %d defeat schedules the next phase" % phase)
		check(until(func() -> bool: return not boss.phase_transition.active), "phase %d handoff completes" % phase)
		check(boss.phase == phase + 1 and boss.combat_stats.health == boss.combat_stats.max_health, "phase %d handoff restores the next health bar" % phase)
		check(is_instance_valid(nodule) and nodule.support_registered, "phase %d handoff preserves permanent root terrain" % phase)
		check(not player.boss_controlled, "phase %d roar releases player control" % phase)
		if phase < 3:
			check(music.music_player.stream == first_stream and music.current_music_path == Chapter1Music.FINAL_BOSS.resource_path and music.music_player.get_playback_position() >= 11.9, "phase %d handoff preserves Forest BOSS 1 playback" % phase)
		else:
			check(music.current_music_path == Chapter1Music.FINAL_BOSS_VINE.resource_path and music.music_player.playing and (music.music_player.stream as AudioStreamMP3).loop, "fourth-phase handoff switches to looping Forest BOSS 2")
	check(boss.state == DeerBoss.State.VINE and vine.step == DeerVinePhase.Step.TRANSFORM, "wind defeat begins the existing vine transformation rather than ending the encounter")
	reset_player()
	await capture("01_vine_transform")
	check(room._status.text.contains("藤") and player.contextual_special_item == ItemCatalog.WIND_SHIELD, "Fourth phase updates the HUD and exposes the wind-shield essence skill")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "human transformation and ascent finish")
	check(vine.human and vine.shield == 3 and boss.invulnerable and not vine.auto_deflect, "production caster starts shielded without dummy auto-deflect")
	await capture("02_vine_hover")
	var launch := boss.root_phase.spawn_nodule_launch(nodule)
	check(is_equal_approx(launch.ground_y, 555.0), "permanent roots remain grounded while the human caster is hovering")
	var health := boss.combat_stats.health
	boss.receive_hit(1, player.global_position)
	boss.receive_skill_hit(SkillHit.new(), player.global_position)
	check(boss.combat_stats.health == health, "shielded aerial caster cannot be bypassed with melee or skills")
	check(until(func() -> bool: return not (vine.strikes.is_empty() and vine.stampedes.is_empty() and vine.treants.is_empty() and vine.wind == null)), "production AI casts a real vine-phase move automatically")
	await capture("03_vine_spell_active")
	var seen: Dictionary = {}
	var previous: StringName = &""
	var repeats := 0
	var safe_repeats := true
	for i in 300:
		boss.phase_ai.choose(500)
		var id := boss.phase_ai.last_vine_sequence
		seen[id] = true
		repeats = repeats + 1 if id == previous else 1
		if repeats > 2: safe_repeats = false
		previous = id
	check(seen.size() == DeerVinePhase.AI_CHOICES.size() and safe_repeats and not seen.has(&"ultimate"), "AI uses all %d vine moves without a third consecutive repeat and no ultimate at full health" % DeerVinePhase.AI_CHOICES.size())
	boss.combat_stats.health = boss.combat_stats.max_health / 2
	boss.phase_ai.choose(500)
	check(vine.sequence_id == &"ultimate" and vine.ultimate_used, "AI opens with the ultimate once at half health")
	vine.cancel()
	vine._enter(DeerVinePhase.Step.HOVER)
	boss.phase_ai.choose(500)
	check(vine.sequence_id != &"ultimate", "the ultimate is used only once per fight")
	boss.combat_stats.health = boss.combat_stats.max_health
	if not output.is_empty():
		reset_vine()
		vine.start_sequence(&"curtain")
		tick(ceili(maxf(0.0, vine.release_time() - DeerVinePhase.RED_LEAD + 0.02) * 60.0))
		await capture("03b_vine_red_warning")
	reset_vine()
	player.air_state = LanPlayer.AirState.FALLING
	tick(90)
	check(vine.step == DeerVinePhase.Step.HOVER and vine.strikes.is_empty(), "new casts wait for a grounded player")
	reset_player()
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.CAST), "casting resumes when the player returns to the ground")
	reset_vine()
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var normal := contact(&"pierce")
	check(normal.snapped and normal.hitbox.attack == null, "actual normal parry snaps the pierce and disables player damage")
	check(until(func() -> bool: return normal.finished), "snapped vine clears itself")
	check(vine.shield == 2 and boss.combat_stats.health == boss.combat_stats.max_health, "normal parry cracks one armour arc without bypassing the armour")
	reset_player()
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var heavy := contact(&"curtain")
	check(heavy.snapped and player.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "actual red counter snaps the curtain")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.STAGGER), "red counter breaks the remaining two arcs and drops the caster")
	check(vine.shield == 0 and boss.poise_broken and not boss.invulnerable and is_equal_approx(boss.position.y, 555), "grounded caster exposes the existing broken-poise damage window")
	await capture("04_vine_ground_window")
	health = boss.combat_stats.health
	boss.receive_hit(1, player.global_position)
	boss.receive_skill_hit(SkillHit.new(), player.global_position)
	check(boss.combat_stats.health == health - 40 and boss.interrupt_with_break_special(), "ground window accepts normal and skill damage and exposes the MAX special contract")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.RISE), "four-second ground window ends with the authored rise")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "caster returns to its casting point")
	check(vine.shield == 3 and vine.cycle == 1 and is_equal_approx(vine.pace(), 1.15) and boss.invulnerable, "next round restores the shield and increases cast pace by 15 percent")
	await capture("05_vine_recovery")
	reset_vine()
	vine.start_sequence(&"ground_lash")
	var before := vine._time
	tick(12, 0.25)
	check(is_equal_approx(vine._time - before, 0.05), "vine casting advances on the quarter-speed action clock")
	reset_vine()
	var gold := contact(&"ground_lash")
	check(gold.hitbox.hit_targets.has(player.get_instance_id()) and not gold.snapped, "gold ground lash cannot be snapped")
	reset_vine()
	assist.set_player_invincible(false)
	player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	var guarded := contact(&"curtain")
	check(player.combat_stats.health == player.combat_stats.max_health - 10 and not guarded.snapped and vine.shield == 3, "ordinary guard takes half curtain damage without snapping the vine")
	reset_vine()
	vine.shield = 1
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	contact(&"pierce")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.STAGGER), "last arc parried: caster grounded for the final blow")
	boss.combat_stats.health = 20
	vine.spawn_strike(&"ground_lash", player.position.x, player.position.x - 300.0, 1.0)
	boss.receive_skill_hit(SkillHit.new(), player.global_position)
	check(boss.state == DeerBoss.State.PHASE_END, "lethal ground-window hit enters the final defeat flow")
	check(vine.strikes.is_empty() and boss.invulnerable and boss.phase_transition.to_phase == 0, "final defeat immediately cancels vines and has no fifth phase")
	check(until(func() -> bool: return boss.state == DeerBoss.State.COMPLETE), "fourth-phase human fall finishes the encounter")
	check(boss.animated_sprite.animation == &"human_fall_ING" and is_equal_approx(boss.position.y, 555), "defeated human stays on the ground without snapping back to a deer")
	await capture("06_vine_defeat")
	check(completed == [1, 2, 3, 4] and room._status.text.contains("已击破") and room._save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "completion signals and saved victory cover all four phases exactly once")
	check(boss.root_phase.nodules.is_empty() and player.sloped_ground_surfaces.is_empty(), "final defeat clears permanent root terrain")
	player.animated_sprite.animation = &"red_parry_success"
	player.defense_state = LanPlayer.DefenseState.RED_PARRY_SUCCESS
	var expired_source := DeerVineStrike.new()
	room.add_child(expired_source)
	player.red_parry_source = expired_source
	expired_source.queue_free()
	await process_frame; await process_frame
	player.on_player_animation_frame_changed()
	player.on_animation_finished()
	check(player.red_parry_source == null, "red counter can finish safely after its projectile source is freed")
	reset_vine()
	assist.set_player_invincible(false)
	player.combat_stats.health = 1
	var fatal := contact(&"pierce")
	check(player.combat_stats.health == 0 and fatal.finished and fatal.is_queued_for_deletion() and vine.strikes.is_empty(), "lethal vine cancels itself safely from inside the player's death callback")
	await process_frame; await process_frame
	boss.set_physics_process(false)
	check(boss.phase == 1 and not vine.human and vine.step == DeerVinePhase.Step.NONE and player.combat_stats.health == player.combat_stats.max_health, "death in vine phase retries from mist with full health and no human state")
	check(music.current_music_path == Chapter1Music.FINAL_BOSS.resource_path and music.music_player.playing, "fourth-phase death restores Forest BOSS 1 on retry")
	reset_vine()
	var abandoned := vine.spawn_strike(&"curtain", player.position.x, player.position.x - 300.0, 0.0, player.global_position + Vector2(-300, -250))
	check(not abandoned.finished, "retry cleanup fixture has a pending vine")
	room._revive()
	check(abandoned.finished and vine.strikes.is_empty() and vine.leaves.is_empty(), "retry immediately clears pending vine damage and leaves")
	await process_frame; await process_frame
	boss.set_physics_process(false)
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "production regression does not modify the user's story progress")
	room.queue_free()
	await process_frame; await process_frame
	var preview = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(preview); current_scene = preview
	await process_frame; await process_frame
	preview.select_combo(4)
	var preview_boss := preview.adapter.get("deer") as DeerBoss
	preview_boss.set_physics_process(false)
	preview.player.set_physics_process(false)
	preview.set_physics_process(false)
	preview.play_action(0)
	for i in 600: preview_boss._physics_process(1.0 / 60)
	check(preview_boss.manual_control and preview_boss.vine_phase.human and preview_boss.vine_phase.step == DeerVinePhase.Step.HOVER, "development-room human preview still uses manual controls")
	check(preview_boss.vine_phase.strikes.is_empty(), "development-room caster does not start production AI")
	preview.play_action(2)
	for i in 30: preview_boss._physics_process(1.0 / 60)
	check(preview_boss.vine_phase.human and preview_boss.vine_phase.sequence_id == &"stampede", "development-room stampede still runs through the shared vine phase")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "development-room verification leaves the story save unchanged")
	preview.queue_free()
	await process_frame; await process_frame
	await create_timer(0.3, true, false, true).timeout
	print("FOUR_PHASE_PRODUCTION: %d checks, %d failures" % [checks, failures])
	call_deferred("quit", 1 if failures else 0)
