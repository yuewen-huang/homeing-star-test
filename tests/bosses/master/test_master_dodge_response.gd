extends "../../support/harness.gd"
var master: MasterBoss
var player: LanPlayer
var rewards := 0

func press_comic_key(code: Key = KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func skip_comic() -> void:
	if master.dodge_response != null and master.dodge_response.comic != null:
		press_comic_key(KEY_ESCAPE)

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	master = room.get_node("MasterBoss")
	player = room.get_node("Lan")
	master.set_process(false)
	player.set_physics_process(false)
	master.flying_sword_enabled = false
	master.attack_hitbox.set_physics_process(false)
	player.global_position = master.to_global(Vector2(-80, 0))
	player.attack_state = LanPlayer.AttackState.ATTACK_1X
	player.air_state = LanPlayer.AirState.GROUNDED
	player.facing_direction = 1
	for i in 3:
		master._start_drink()
		master._finish_drink()
	check(master.charged_power == 3 and not master.evades_attack(player, true), "Three completed drinks do not arm a special evasion")
	master._start_drink()
	check(not master.evades_attack(player, true) and not master.dodge_response_ready, "Starting the fourth gulp is not enough")
	master._finish_drink()
	check(master.charged_power == 4 and master.dodge_response_ready, "Only completion of the fourth gulp arms the response")
	check(not master.evades_attack(player, false) and master.dodge_response_ready, "Detached effects and skills cannot spend the opportunity")
	player.air_state = LanPlayer.AirState.RISING
	check(not master.evades_attack(player, true), "Wait for a grounded attack")
	player.air_state = LanPlayer.AirState.GROUNDED
	player.global_position = master.to_global(Vector2(-1000, 0))
	check(not master.evades_attack(player, true), "Remote attacks cannot start a cross-arena response")
	player.global_position = master.to_global(Vector2(-80, 0))
	master.poise_broken = true
	check(not master.evades_attack(player, true), "Broken poise keeps the opening and preserves the opportunity")
	master.poise_broken = false
	# Real production collision route: an evaded contact emits no hit_landed/rewards.
	var effect := load("res://scenes/player/lan/lan_attack_effect.tscn").instantiate() as Node2D
	effect.setup(player, 1.0, LanAttackEffectCatalog.attack_1x(), true)
	player.add_child(effect)
	effect.position = Vector2(0, -55)
	effect.set_physics_process(false)
	effect.set_timeline_frame(2)
	effect.hit_landed.connect(func(_target: DamageReceiver2D) -> void: rewards += 1)
	await physics_frame
	await physics_frame
	var health := master.combat_stats.health
	var poise := master.combat_stats.poise
	effect._physics_process(0.01)
	check(master.dodge_response != null and master.dodge_response_used and not master.dodge_response_ready, "Actual blade overlap spends exactly one armed response")
	check(master.combat_stats.health == health and master.combat_stats.poise == poise and rewards == 0, "Dodged blade gives no damage, poise or hit rewards")
	if master.dodge_response == null:
		finish("MASTER DODGE RESPONSE")
		return
	var response := master.dodge_response
	master.receive_hit(1, player.global_position)
	master.receive_attack_hit(AttackHitContext.new(&"test", 9999, 9999), player.global_position)
	master.receive_skill_hit(SkillHitContext.new(&"test",9999), player.global_position)
	check(master.combat_stats.health == health and not master.can_be_interrupted_by_special(), "Committed evasion remains safe from follow-up hit paths and interruptions")
	var start_x := master.position.x
	master._process(0.8)
	check(master.position.x != start_x and master.animated_sprite.animation == &"skill_dodge", "Roll moves the real boss while authored frames play")
	check(not player.evaded_action_clock.is_slowed(), "Slowdown begins after the roll")
	master._process(0.8)
	check(response.stage == MasterDodgeResponse.Stage.COMIC and response.comic != null, "Finishing the roll automatically opens the comic without an interaction")
	check(paused and player.input_frozen and not player.evaded_action_clock.is_slowed(), "Comic pauses combat before the finger-flick slowdown starts")
	var comic := response.comic
	check(comic is ComicPlayer and comic._frames.size() == 6 and comic.panel_index == 0, "Shared ComicPlayer splits the supplied page into six panels in reading order")
	check(comic._frames.all(func(frame: Texture2D): return frame is AtlasTexture and (frame as AtlasTexture).atlas == MasterDodgeComic.COMIC), "Every panel uses a region of the unchanged original artwork")
	response.advance(10.0)
	check(response.stage == MasterDodgeResponse.Stage.COMIC and response.elapsed == 0 and not response.landed, "Reading time cannot consume the response or settle hidden damage")
	comic.panel_fade_duration = 0
	for i in 5:
		press_comic_key()
		check(comic.panel_index == i+1 and response.stage == MasterDodgeResponse.Stage.COMIC, "Reading panel %d leaves combat paused" % (i+2))
	press_comic_key()
	check(not paused and not player.input_frozen and response.comic == null, "Finishing the sixth panel restores the prior pause and input state")
	check(response.stage == MasterDodgeResponse.Stage.FLICK and player.evaded_action_clock.is_slowed(), "Roll hands off to finger flick and shared local bullet time")
	check(player.evaded_action_clock.dodge_remaining >= response.duration("finger_flick"), "Slowdown budget covers every finger-flick frame")
	var player_at := player.position
	player.end_evaded_action_slow(response)
	player.velocity = Vector2(120,0)
	player.move_on_action_clock()
	var normal_travel := player.position.x - player_at.x
	player.position = player_at
	player.begin_evaded_action_slow(response,response.duration("finger_flick")+0.1)
	player.velocity = Vector2(120,0)
	player.move_on_action_clock()
	check(normal_travel > 0 and is_equal_approx((player.position.x-player_at.x)/normal_travel,ActionClock.DODGE_SLOW), "Physics displacement actually slows, not just the movement timers")
	player.position = player_at
	player._set_body_speed(1.3)
	player._set_timeline_speed(1.4)
	check(is_equal_approx(player.animated_sprite.speed_scale,1.3 * ActionClock.DODGE_SLOW) and is_equal_approx(player.combat_timeline.speed_scale,1.4 * ActionClock.DODGE_SLOW), "Body and combat timeline share local slowdown, including new animations")
	var player_health := player.combat_stats.health
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	master._process(1.69)
	check(player.combat_stats.health == player_health, "Finger flick cannot damage during its wind-up")
	master._process(0.02)
	check(player.combat_stats.health == player_health - 1 and response.landed, "Extended finger settles precisely one HP despite a guard")
	master._process(1.38)
	check(player.evaded_action_clock.is_slowed() and player.combat_stats.health == player_health-1, "Bullet time remains through the authored retreat without repeated damage")
	check(not master.evades_attack(player,true), "Only the roll evades: finger-flick recovery grants no extra invulnerability")
	master.receive_hit(1,player.global_position)
	check(master.combat_stats.health < health and master.dodge_response == response, "Master remains damageable after the roll without losing the authored flick")
	master._process(0.12)
	check(response.stage == MasterDodgeResponse.Stage.LAUGH and not player.evaded_action_clock.is_slowed() and response.bubble.visible, "Full clip finishes before slowdown clears and the taunt appears")
	check(is_equal_approx(player.animated_sprite.speed_scale, player.body_base_speed) and is_equal_approx(player.combat_timeline.speed_scale,player.timeline_base_speed), "Normal animation speeds restore exactly")
	master._process(0.61)
	check(master.dodge_response == null and master.state == MasterBoss.State.CHASE, "Laugh ends in ordinary AI without repeating the response")
	player.global_position = master.to_global(Vector2(-80,0))
	player.defense_state = LanPlayer.DefenseState.NONE
	check(not master.evades_attack(player,true), "The fourth-layer opportunity is permanently used for this encounter")
	master.receive_hit(1,player.global_position)
	check(master.combat_stats.health < health, "Normal damage resumes after the special response")
	effect.free()
	# The development hook uses the same executor. Cancellation and phase handoff restore it.
	master.manual_control = true
	master.start_dodge_response(player)
	master._process(1.61)
	skip_comic()
	check(not paused and master.dodge_response.stage == MasterDodgeResponse.Stage.FLICK, "Esc skips the comic once and resumes the same finger-flick response")
	var before := player.combat_stats.health
	master._process(1.8)
	check(player.combat_stats.health == before, "Manual preview never damages its observer")
	master._enter_phase_2()
	check(master.dodge_response == null and not player.evaded_action_clock.is_slowed() and not master.dodge_response_ready, "Phase handoff cancels visuals, local slowdown and the pending opportunity")
	master.phase = 1
	master.start_dodge_response(player)
	master._process(1.61)
	check(paused and master.dodge_response.comic != null, "A preview also opens the real shared comic after its roll")
	master._enter_phase_2()
	check(not paused and not player.input_frozen and master.dodge_response == null, "Phase handoff during the comic restores pause and input without starting a flick")
	master.phase = 1
	master.start_dodge_response(player)
	master._process(1.61)
	var abandoned := master.dodge_response.comic
	abandoned.free()
	check(not paused and not player.input_frozen and master.dodge_response == null, "External comic teardown cancels the response without leaving the world frozen")
	master.start_dodge_response(player)
	player.input_frozen = true
	paused = true
	master.dodge_response.advance(1.61)
	var cancelled_comic := master.dodge_response.comic
	master.cancel_dodge_response()
	cancelled_comic.playback_finished.emit(false)
	check(paused and player.input_frozen and not player.evaded_action_clock.is_slowed(), "Cancellation preserves an earlier pause/freeze and ignores stale comic completion")
	paused = false
	player.input_frozen = false
	master.phase = 1
	master.manual_control = false
	master.start_dodge_response(player)
	master._process(1.61)
	skip_comic()
	player.combat_stats.health = 0
	master._process(0.01)
	check(master.dodge_response == null and not player.evaded_action_clock.is_slowed(), "Player defeat clears the response immediately")
	player.combat_stats.restore_health()
	master.start_dodge_response(player)
	master._process(1.61)
	skip_comic()
	master.free()
	check(not player.evaded_action_clock.is_slowed(), "Freeing the boss during bullet time restores the player's speed")
	room.free()
	current_scene = null
	await process_frame
	expect_save_untouched()
	finish("MASTER DODGE RESPONSE")
