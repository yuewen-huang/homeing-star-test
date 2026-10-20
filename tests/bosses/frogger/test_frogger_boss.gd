extends SceneTree

class LocalProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass
	func is_ability_unlocked(_ability: StringName) -> bool: return true

class LocalEncounter extends "res://scripts/levels/back_alley/back_alley_encounter.gd":
	func _ready() -> void: pass

class NativeAlley extends "res://scripts/levels/back_alley/back_alley.gd":
	func _add_slime_encounter() -> void: pass

var room
var frog: FroggerBoss
var failures := 0
var checks := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(count: int, speed := 1.0) -> void:
	for frame in count:
		frog._physics_process(speed / 60.0)
		room._physics_process(speed / 60.0)

func capture(label: String) -> void:
	if output.is_empty(): return
	room._process(0)
	room.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Godot capture " + label)

func start(index: int, x := 688.0) -> void:
	room.dummy_x.value = x
	room.play_action(index)

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT") if DisplayServer.get_name() != "headless" else ""
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(3)
	await process_frame
	frog = room.adapter.boss as FroggerBoss
	frog.set_physics_process(false)
	room.player.set_physics_process(false)
	check(room.boss_picker.get_item_text(3).contains("蛤蟆") and frog is BossBase, "fourth catalog entry uses production Frogger combat class")
	check(frog.manual_control and not frog.is_in_group(&"damageable") and frog.get_node("Hurtbox").collision_layer == 0, "manual specimen cannot be damaged or auto-select actions")
	check(frog.animated_sprite.sprite_frames.get_frame_count(&"idle") == 5 and frog.animated_sprite.sprite_frames.get_frame_count(&"tongue") == 8 and frog.animated_sprite.sprite_frames.get_frame_count(&"heal") == 17, "128px idle and 384px action cells preserve correct frame counts")
	var tongue_tex := frog.animated_sprite.sprite_frames.get_frame_texture(&"tongue", 3) as AtlasTexture
	check(tongue_tex.region == Rect2(1152, 0, 384, 128) and frog.animated_sprite.scale == Vector2.ONE * 1.4 and is_equal_approx(frog.animated_sprite.position.y, -89.6), "full extended tongue and uniform foot pivot retained")
	var origin := frog.position
	tick(720)
	check(frog.action == &"idle" and frog.position == origin and frog.attack_hitbox.attack == null, "manual frog stays idle for twelve seconds")
	await capture("frogger_idle")
	for speed in [1.0, 0.5, 0.25]:
		start(0)
		tick(roundi(0.19 * 60 / speed), speed)
		check(frog.attack_hitbox.attack == null and room.dummy.contacts.is_empty(), "tongue warning has no premature damage at speed %.2f" % speed)
		if speed == 1.0: await capture("frogger_tongue_warning")
		tick(roundi(0.18 * 60 / speed), speed)
		check(frog.animated_sprite.frame == 3 and room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 10, "real F3 extended tongue hits once at speed %.2f" % speed)
		if speed == 1.0:
			room.show_hitboxes = true
			await capture("frogger_tongue_active")
			room.show_hitboxes = false
		tick(roundi(0.45 * 60 / speed), speed)
		check(frog.action == &"idle" and frog.attack_hitbox.attack == null and room.dummy.contacts.size() == 1, "tongue recovery closes one segment at speed %.2f" % speed)
	start(0, 960)
	tick(23)
	check(frog.direction > 0 and room.dummy.contacts.size() == 1 and frog.attack_collision.position.x > 0, "right-facing tongue mirrors actual hitbox")
	await capture("frogger_tongue_right")
	start(0, 400)
	tick(60)
	check(room.dummy.contacts.is_empty(), "far target cannot be reached by oversized hidden tongue")
	start(1, 630)
	tick(40)
	check(frog.attack_hitbox.attack == null and room.dummy.contacts.is_empty(), "spit inflation does not deal damage before F7")
	await capture("frogger_spit_warning")
	tick(6)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == CombatTuning.BOSS_PLAYER_NORMAL_DAMAGE and frog.animated_sprite.frame == 7, "painted water contacts once at F7")
	room.show_hitboxes = true
	await capture("frogger_spit_active")
	room.show_hitboxes = false
	tick(23)
	check(frog.action == &"idle" and frog.attack_hitbox.attack == null and room.dummy.contacts.size() == 1, "moving water keeps one attack ID and closes after recovery")
	await capture("frogger_recovery")
	start(1, 400)
	tick(80)
	check(room.dummy.contacts.is_empty(), "spit does not invent an unpainted long-range projectile")
	start(2)
	tick(30)
	check(frog.position.x < origin.x and room.dummy.contacts.is_empty() and frog.attack_hitbox.attack == null, "real hop moves without body contact damage")
	await capture("frogger_move")
	tick(30)
	check(is_equal_approx(frog.position.x, 788.0), "hop stops 100px before locked dummy")
	start(0)
	check(frog.position == origin, "replaying any action restores development origin")
	tick(23)
	var cancelled_attack := frog.attack_hitbox.attack
	frog.interrupt_with_special()
	check(frog.action == &"hurt" and frog.attack_hitbox.attack == null and cancelled_attack != null, "special interruption closes active tongue immediately")
	tick(100)
	check(frog.action == &"idle" and frog.attack_hitbox.attack == null, "interrupted attack cannot resume a stale delayed contact")
	start(3)
	frog.combat_stats.health = 100
	tick(55)
	var healed_health := 100 + roundi(CombatTuning.FROGGER_HEALTH * CombatTuning.FROGGER_HEAL_RATIO)
	check(frog.combat_stats.health == healed_health and room.dummy.contacts.is_empty(), "authored heal restores shared ratio only at F9 and has no damage")
	await capture("frogger_heal")
	tick(70)
	check(frog.combat_stats.health == healed_health, "heal only settles once per action")
	start(3)
	frog.receive_hit(1, Vector2.ZERO)
	check(frog.action == &"hurt", "normal hit interrupts healing")
	start(4)
	tick(10)
	await capture("frogger_hurt")
	start(1)
	tick(46)
	room.reset_room()
	await process_frame
	frog = room.adapter.boss as FroggerBoss
	frog.set_physics_process(false)
	check(frog.position == origin and frog.action == &"idle" and frog.attack_hitbox.attack == null and room.dummy.contacts.is_empty(), "R resets the complete specimen and all probes")
	var player_health: int = room.player.combat_stats.health
	room.player.position = Vector2(688, 555)
	start(0)
	tick(90)
	check(room.player.combat_stats.health == player_health, "preview remains no-damage")
	start(1)
	tick(46)
	room.select_boss(2)
	await process_frame
	check(room.specimen.get_child_count() == 1 and room.adapter.boss is TwinFishBoss, "switching an active frog leaves only the selected specimen")
	room.select_boss(3)
	await process_frame
	frog = room.adapter.boss as FroggerBoss
	frog.set_physics_process(false)
	check(room.player.dodge_evaded_attack.get_connections().filter(func(connection: Dictionary) -> bool: return connection.callable.get_object() is FroggerBoss).size() == 1, "switching does not accumulate frog player-signal connections")
	await test_encounter()
	current_scene = null
	room.free()
	await process_frame
	await test_native_alley()
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "all previews and local encounter tests preserve real save bytes")
	print("FROGGER: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func test_encounter() -> void:
	room.adapter.dispose()
	room.specimen.free()
	room.adapter = null
	var progress := LocalProgress.new()
	room.add_child(progress)
	var encounter := LocalEncounter.new()
	encounter.setup(room.player, room, 555.0, 1020.0)
	encounter.save = progress
	room.add_child(encounter)
	room.player.position = Vector2(500, 555)
	room.player.world_max_x = 1800
	encounter._enter_fifth_wave()
	frog = encounter.frog_boss
	frog.set_physics_process(false)
	check(frog != null and not frog.manual_control and frog.tutorial_protected and encounter.current_wave == 5, "fifth wave spawns a real autonomous frog instead of training dummy")
	check(room.player.world_max_x < 1800, "road remains blocked until frog defeat")
	var normal := SkillHitContext.new(&"lan_special_attack", 18)
	var max_hit := SkillHitContext.new(&"lan_special_attack", 60, false, false, false, true)
	frog.receive_skill_hit(max_hit, Vector2.ZERO)
	check(not progress.has_completed(SaveProgressService.STORY_BACK_ALLEY_SPECIAL_MAX_USED), "Max before normal demonstration cannot complete tutorial")
	frog.receive_skill_hit(normal, Vector2.ZERO)
	check(progress.has_completed(SaveProgressService.STORY_BACK_ALLEY_SPECIAL_NORMAL_USED) and not frog.is_poise_broken(), "normal special registers without prematurely breaking poise")
	for hit in ceili(float(CombatTuning.FROGGER_HEALTH) / CombatTuning.BOSS_LIGHT_HIT_HEALTH) + 2: frog.receive_hit(1, Vector2.ZERO)
	check(frog.combat_stats.health == 1 and frog.poise_broken and not progress.has_completed(SaveProgressService.STORY_BACK_ALLEY_SLIMES_DEFEATED), "tutorial preserves last HP and leaves a broken-poise Max window")
	frog.receive_skill_hit(max_hit, Vector2.ZERO)
	check(progress.has_completed(SaveProgressService.STORY_BACK_ALLEY_SPECIAL_TUTORIAL_COMPLETE) and not frog.tutorial_protected and frog.combat_stats.health == 0, "broken Max completes lesson, removes protection and settles killing damage")
	for frame in 60: frog._physics_process(1.0 / 60)
	check(progress.has_completed(SaveProgressService.STORY_BACK_ALLEY_SLIMES_DEFEATED) and encounter.frog_boss == null and room.player.world_max_x == 1800, "defeat clears fifth wave and restores road boundary")
	await process_frame
	encounter._enter_fifth_wave()
	check(encounter.frog_boss == null, "old cleared save does not replay frog")
	progress._config = ConfigFile.new()
	progress.mark_completed(SaveProgressService.STORY_BACK_ALLEY_SPECIAL_TUTORIAL_COMPLETE)
	encounter._enter_fifth_wave()
	frog = encounter.frog_boss
	frog.set_physics_process(false)
	check(frog != null and not frog.tutorial_protected, "completed lesson with unfinished battle resumes live fifth wave")
	frog.start_action(&"tongue", Vector2(500,555))
	frog._physics_process(0.35)
	room.player.combat_stats.health = 0
	encounter._process(0)
	check(encounter.state == encounter.State.RESPAWNING and encounter.frog_boss == null, "player defeat cancels attack and removes failed encounter")
	await create_timer(1.0).timeout
	frog = encounter.frog_boss
	frog.set_physics_process(false)
	check(room.player.combat_stats.health == 100 and frog.combat_stats.health == CombatTuning.FROGGER_HEALTH and not frog.tutorial_protected, "retry rebuilds clean boss while retaining completed lesson")
	# Production AI and shared player damage/guard/parry contracts, outside preview.
	frog.combat_target = room.player
	frog._cooldown = 0.0
	frog._physics_process(1.0 / 60)
	check(frog.action != &"idle", "production frog automatically selects its first action")
	frog._idle()
	frog._heal_used = false
	frog.combat_stats.health = 100
	frog._cooldown = 0.0
	frog._physics_process(1.0 / 60)
	check(frog.action == &"heal", "production AI uses one healing action below half health")
	encounter._remove_frog_boss()
	await process_frame
	var player := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.save_progress = progress
	player.save_progress_resolved = true
	player.position = Vector2(500,555)
	player.world_min_x = 32
	player.world_max_x = 1800
	room.add_child(player)
	player.set_physics_process(false)
	frog = FroggerBoss.new()
	frog.combat_target = player
	frog.manual_control = true
	frog.position = Vector2(650,555)
	room.add_child(frog)
	frog.set_physics_process(false)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var prior_difficulty := assist.difficulty
	var prior_invincible := assist.player_invincible
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	frog.start_action(&"tongue")
	frog._physics_process(0.35)
	check(player.combat_stats.health == 90, "production tongue deals ten HP through the real player hurtbox")
	frog._physics_process(0.05)
	check(player.combat_stats.health == 90, "same active tongue cannot hit real player twice")
	player.reset_after_map_fall(Vector2(500,555))
	player.combat_stats.restore_health()
	player.start_parry_nothing()
	frog.start_action(&"tongue")
	frog._physics_process(0.35)
	check(player.combat_stats.health == 95 and player.defense_state == LanPlayer.DefenseState.PARRY_FAILURE, "real ordinary guard takes half tongue damage")
	player.reset_after_map_fall(Vector2(500,555))
	player.combat_stats.restore_health()
	player.start_parry(true)
	frog.start_action(&"tongue")
	frog._physics_process(0.35)
	check(player.combat_stats.health == 100 and frog.combat_stats.poise == CombatTuning.FROGGER_POISE - CombatTuning.BOSS_NORMAL_PARRY_POISE, "real successful parry preserves health and removes shared frog poise")
	for counter in ceili(float(CombatTuning.FROGGER_POISE) / CombatTuning.BOSS_NORMAL_PARRY_POISE) - 1:
		player.reset_after_map_fall(Vector2(500,555))
		player.start_parry(true)
		frog._parry_pause = 0
		frog.start_action(&"tongue")
		frog._physics_process(0.35)
	check(frog.poise_broken and frog.action == &"hurt" and frog.attack_hitbox.attack == null, "shared parries break frog poise and cancel the attack")
	assist.set_difficulty(prior_difficulty)
	assist.set_player_invincible(prior_invincible)
	frog.free()
	player.free()
	encounter.free()
	progress.free()
	await process_frame

func test_native_alley() -> void:
	var progress := LocalProgress.new()
	root.add_child(progress)
	progress.mark_completed(SaveProgressService.STORY_BACK_ALLEY_WAVE_4_CLEARED)
	var alley := NativeAlley.new()
	root.add_child(alley)
	current_scene = alley
	alley.save_progress = progress
	alley.player.save_progress = progress
	alley.player.save_progress_resolved = true
	alley.player.set_physics_process(false)
	alley.player.position.x = 1250
	alley._process(0)
	alley.set_process(false)
	var encounter := LocalEncounter.new()
	encounter.save = progress
	encounter.setup(alley.player, alley.world_root, alley.FLOOR_Y, 1020)
	alley.add_child(encounter)
	encounter._enter_fifth_wave()
	encounter.set_process(false)
	frog = encounter.frog_boss
	frog.set_physics_process(false)
	check(frog.global_position.distance_to(alley.player.global_position) < 200 and frog.position.y == alley.FLOOR_Y, "native scrolling alley shares correct player/boss foot coordinates")
	check(frog.get_node("BossStatusHUD").portrait.texture != null, "production HUD uses frog artwork")
	if not output.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join("frogger_alley_idle.png")) == OK, "Godot capture actual alley fifth wave")
	frog.start_action(&"tongue")
	frog._physics_process(0.35)
	check(frog.direction < 0 and frog.attack_hitbox.attack != null and frog.attack_collision.global_position.x < frog.global_position.x, "production attack follows scrolling world and faces real player")
	if not output.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join("frogger_alley_tongue.png")) == OK, "Godot capture actual alley tongue")
	current_scene = null
	alley.free()
	progress.free()
	await process_frame
