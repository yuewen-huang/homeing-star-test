extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const TOAD := preload("res://scripts/levels/chapter_2_underwater/cavern/cavern_bronze_toad.gd")
const ATTACK := preload("res://scripts/levels/chapter_2_underwater/cavern/cavern_toad_attack.gd")
const FIGHT_AT := TOAD.ORIGIN + Vector2(-360, 0)
const STRIKE_AT := TOAD.ORIGIN + Vector2(-40, 0)
const BLOCK_X := TOAD.ORIGIN.x + TOAD.BODY_SOLID.position.x

var level: SunkenCavern
var toad: TOAD
var player: LanPlayer
var combos: Dictionary = {}
var sampled: Dictionary = {}
var hazard_kinds: Dictionary = {}
var output := ""
var longest_flight := 0.0
var drag_continuous := true
var camera_stable := true
var most_airborne_stakes := 0
var most_live_stakes := 0


func run() -> void:
	seed(25)
	var save := use_memory_progress()
	save.try_complete_fact(&"sunken_cavern_bell_awake")
	level = SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	toad = level.bronze_toad
	player = level.player
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.difficulty = BattleAssistSettingsService.Difficulty.HARD
	assist.set_player_invincible(false)
	toad.combination_started.connect(func(index: int) -> void: combos[index] = true)
	await physics_frame
	check(toad.is_visible_in_tree() and not toad.engaged and not toad._blocker.disabled, "fixed guard exists at A25")
	var cross := PhysicsRayQueryParameters2D.create(Vector2(7820, 5200), Vector2(7940, 5200), 1)
	check(level.get_world_2d().direct_space_state.intersect_ray(cross).is_empty() \
		and not level.resonance.has_map_item(), "A27 passage has no echo gate on a fresh save")
	toad.set_physics_process(false)
	player.reset_after_map_fall(level.marker("ante"))
	Input.action_press(&"ui_right")
	for i in 150: await physics_frame
	Input.action_release(&"ui_right")
	check(player.global_position.x > 7970.0 and not level.resonance.has_map_item(),
		"real Lan input passes the old A27 seal without any echoes")
	player.reset_after_map_fall(TOAD.ORIGIN + Vector2(-100, 0))
	Input.action_press(&"ui_right")
	for i in 100: await physics_frame
	Input.action_release(&"ui_right")
	check(player.global_position.x < BLOCK_X and player.global_position.x > TOAD.ORIGIN.x - 20.0,
		"real Lan movement stops at the physical guard (x=%.1f)" % player.global_position.x)
	Input.action_press(&"ui_right")
	Input.action_press(&"jump")
	for i in 10: await physics_frame
	Input.action_release(&"jump")
	Input.action_press(&"instant_dash")
	for i in 47: await physics_frame
	Input.action_release(&"instant_dash")
	Input.action_release(&"ui_right")
	check(player.global_position.x < BLOCK_X, "a real jump and air dash cannot cross the intact guard")
	player.reset_after_map_fall(STRIKE_AT)
	player.facing_direction = 1.0
	await physics_frame
	var guard_health := toad.combat_stats.health
	var strike := InputEventKey.new()
	strike.physical_keycode = KEY_J
	strike.pressed = true
	Input.parse_input_event(strike)
	for i in 3: await physics_frame
	strike = InputEventKey.new()
	strike.physical_keycode = KEY_J
	Input.parse_input_event(strike)
	for i in 33: await physics_frame
	check(toad.combat_stats.health < guard_health, "real J input damages the guard through its front hurtbox")
	toad.reset_attempt()
	player.reset_after_map_fall(TOAD.RETRY_AT)
	level.snap_camera()
	await capture("01_approach")
	var half_view := level.get_viewport_rect().size.x * 0.5 / level.camera.zoom.x
	check(level.camera.zoom.is_equal_approx(Vector2.ONE) \
		and level.camera.position.x + half_view >= TOAD.ORIGIN.x + 150.0,
		"ordinary approach framing shows the front of the guard at normal zoom")
	level.tide.time = 0.0
	toad.set_physics_process(true)
	Input.action_press(&"ui_right")
	for i in 90:
		await physics_frame
		if toad.engaged and player.global_position.x >= FIGHT_AT.x: break
	Input.action_release(&"ui_right")
	check(toad.engaged and level.tide._combat_suspended and level.tide.flood.column_wet.is_empty(),
		"approaching normally starts combat with no shaft surge (player=%s)" % player.position)
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.request_camera_punch(0.20)
	feedback.request_screen_shake(0.22, 12.0)
	check(level.camera.zoom.is_equal_approx(Vector2.ONE) and level.camera.offset.is_zero_approx(),
		"combat feedback does not punch or shake the A25 camera")
	var first_health := player.combat_stats.health
	for i in 430:
		await physics_frame
		await sample_states()
		if player.combat_stats.health < first_health or level.drowned_count > 0: break
	check(player.combat_stats.health < first_health or level.drowned_count > 0,
		"standing still with no defense takes damage")

	toad.set_physics_process(false)
	toad.reset_attempt()
	player.reset_after_map_fall(FIGHT_AT)
	level.tide.time = level.tide.CALM + level.tide.WARNING + 4.0
	level.tide._physics_process(0.0)
	check(level.tide.is_surging() and not level.tide.flood.column_wet.is_empty(), "fixture has an active shaft surge")
	check(toad._engage() and not level.tide.is_surging() and level.tide.flood.column_wet.is_empty(),
		"combat start also shuts off an already active shaft surge")

	# After an ordinary engagement, the far left approach is still within the throw's reach.
	player.reset_after_map_fall(Vector2(TOAD.ARENA_LEFT + 185.0, TOAD.ORIGIN.y))
	level.snap_camera()
	check(is_equal_approx(level.camera.position.x, player.global_position.x)
		and level.camera.zoom.is_equal_approx(Vector2.ONE),
		"the far left combat view follows Lan without widening")
	player.combat_stats.restore_health()
	var far_health := player.combat_stats.health
	toad._bag.assign([2])
	toad.set_physics_process(true)
	for i in 320:
		await physics_frame
		await sample_states()
		if player.combat_stats.health < far_health: break
	check(player.combat_stats.health < far_health, "standing at the far left can be hit")

	# Coverage loop uses health refill to see all attacks, separate from the test above.
	toad.reset_attempt()
	player.reset_after_map_fall(FIGHT_AT)
	player.combat_stats.refill_health_on_depletion = true
	toad.set_physics_process(true)
	combos.clear()
	for i in 1510:
		await physics_frame
		await sample_states()
		if combos.size() == 4 and hazard_kinds.size() >= 4 and sampled.has("05_gold_cross") \
				and sampled.has("07_water_jet") and sampled.has("08_ground_spear") \
				and sampled.has("09_ground_drag") and sampled.has("11_needle_rain"):
			break
	check(combos.size() == 4, "all four hammer/ball combinations run through the game scene")
	check(longest_flight >= 1100.0, "the hammer travels %.1f world px on the straight throw" % longest_flight)
	check(sampled.has("09_ground_drag") and drag_continuous,
		"the hammer stays unspun and on the floor through every observed recall frame")
	check(camera_stable, "zoom and offset stay steady through combat while Lan remains the camera subject")
	check(most_airborne_stakes >= 8 and most_live_stakes >= 24,
		"the throw releases three eight-spear fans, with at least eight visibly airborne")
	check(sampled.has("10_spear_lane"), "a pending spear draws a full shared range strip")
	check((toad._assets["spear"][2] as Texture2D).get_width() == 144,
		"the thicker spear loads the higher-density frame")
	check(toad._sphere.radius == TOAD.BALL_RADIUS and TOAD.BALL_RADIUS >= 46.0,
		"the enlarged ball uses the corresponding contact radius")
	for kind in [ATTACK.Kind.STAKE, ATTACK.Kind.SPIKE, ATTACK.Kind.JET, ATTACK.Kind.BOLT]:
		check(hazard_kinds.has(kind), "live hazard kind %d spawned" % kind)
	check(sampled.has("03_roll") and sampled.has("04_hover") and sampled.has("05_gold_cross"),
		"rolling, hovering and gold cross states all advance")

	toad.combat_stats.set_health_ratio(0.36)
	for i in 101: await physics_frame
	await capture("06_low_health")
	toad.set_physics_process(false)
	player.set_physics_process(false)
	toad.reset_attempt()
	player.reset_after_map_fall(FIGHT_AT)
	check(toad._engage(), "reentering restores a fresh attempt")
	toad._release_ball()
	toad._set_ball(TOAD.Ball.ROLL)
	toad._ball_at = Vector2(FIGHT_AT.x + 57.0, TOAD.BALL_FLOOR)
	player.facing_direction = 1.0
	player.start_parry()
	toad._update_ball(0.018)
	var back_from := toad._ball_at.x
	toad._update_ball(0.10)
	toad._update_ball(0.10)
	check(toad._roll_count == 1 and toad._ball_at.x > back_from and not toad._ball_contact.settled,
		"a real parry knocks the ball backward and rearms its next approach")
	toad._ball_at = Vector2(FIGHT_AT.x + 57.0, TOAD.BALL_FLOOR)
	player.start_parry(true)
	toad._update_ball(0.018)
	check(toad._roll_count == 2, "the same ball can be parried twice")
	player.reset_after_map_fall(FIGHT_AT)
	toad._ball_at = Vector2(FIGHT_AT.x + 92.0, TOAD.BALL_FLOOR)
	toad._ball_age = 1.7
	toad._roll_recoil = 0.0
	var cross_health := player.combat_stats.health
	toad._update_ball(0.01)
	toad._update_ball(0.28)
	toad._update_ball(0.40)
	check(toad.ball == TOAD.Ball.THRUST and toad._ball_at.x < player.position.x \
		and player.combat_stats.health == cross_health and toad._hazards.back().direction.x > 0.0,
		"gold ball crosses without contact damage and thrusts back from behind")

	toad.combat_stats.set_health_ratio(0.36)
	toad._physics_process(0.085)
	check(toad._tadpoles.size() == 4, "low health releases four persistent tadpoles")
	if toad._tadpoles.size() < 2:
		finish("A25 BRONZE TOAD")
		return
	var coin := toad._tadpoles[0]
	var ingot := toad._tadpoles[1]
	coin.age = 1.0
	ingot.age = 1.0
	coin.at = toad._rig.head_at()
	ingot.at = FIGHT_AT + Vector2(0, -40)
	toad._touch_tadpoles(toad._sphere, Transform2D(0.0, coin.at), true)
	toad._touch_tadpoles(toad._sphere, Transform2D(0.0, ingot.at), false)
	check(coin.form == TOAD.Spawn.COIN and ingot.form == TOAD.Spawn.INGOT,
		"hammer and ball contacts produce the two different forms")
	toad._flight = Vector2(-TOAD.FLIGHT_SPEED, 0)
	toad._redirect_flight()
	check(absf(toad._flight.y) > 0 and toad._flight.length() > TOAD.FLIGHT_SPEED, "the coin changes hammer direction and speed")
	var normal_move := player.get_horizontal_speed()
	toad._update_tadpoles(0.015)
	player.attack_state = LanPlayer.AttackState.ATTACK_1X
	check(ingot.form == TOAD.Spawn.ATTACHED and player.get_horizontal_speed() < normal_move \
		and player.get_action_time_scale() < 1.0, "an attached ingot slows movement and attack")
	toad.reset_attempt()
	check(toad._ingot == null and toad._tadpoles.is_empty() and not level.tide._combat_suspended \
		and is_equal_approx(player.get_action_time_scale(), 1.0), "reset removes all temporary effects and releases the tide")

	player.reset_after_map_fall(FIGHT_AT)
	player.combat_stats.restore_health()
	check(toad._engage(), "fight can restart to check the widened ground warning")
	toad._spawn_ground(FIGHT_AT.x, false, 0.55)
	var test_spike: ATTACK = toad._hazards.back()
	player.set_physics_process(true)
	Input.action_press(&"ui_left")
	for i in 42:
		await physics_frame
		test_spike.step(1.0 / 60.0)
	Input.action_release(&"ui_left")
	check(player.global_position.x < FIGHT_AT.x - ATTACK.SPIKE_WIDTH * 0.5 \
		and player.combat_stats.health == player.combat_stats.max_health,
		"ordinary movement can leave the widened spike warning before it fires")
	player.set_physics_process(false)
	toad.reset_attempt()

	await test_hover_volley()
	await test_hammer_responses()

	player.reset_after_map_fall(FIGHT_AT)
	player.combat_stats.restore_health()
	check(toad._engage(), "fight can restart to check the rain blast beats")
	toad._sling_spear_rain(FIGHT_AT + Vector2(42, -145))
	var first: ATTACK = toad._hazards[0]
	var third: ATTACK = toad._hazards[2]
	var overlap_x := (first.endpoint.x + third.endpoint.x) * 0.5
	player.reset_after_map_fall(Vector2(overlap_x, TOAD.ORIGIN.y))
	var rain_health := player.combat_stats.health
	first.step(first.cue + 0.08)
	third.step(third.cue + 0.08)
	check(first.impact_beat == third.impact_beat and first.impact_beat.spent \
		and player.combat_stats.health == rain_health - first.attack.health_damage,
		"overlapping blasts on the same rain beat settle one hit")
	toad.reset_attempt()

	player.reset_after_map_fall(FIGHT_AT)
	check(toad._engage(), "fight restarts for victory settlement")
	var jet_health := player.combat_stats.health
	toad._spawn_ground(player.global_position.x, true, 0.02)
	toad._hazards.back().step(0.17)
	check(player.velocity.y < 0.0 and player.combat_stats.health == jet_health,
		"a slam jet launches through Lan's real hurtbox without damage")
	toad.combat_stats.apply_health_damage(toad.combat_stats.max_health)
	await physics_frame
	await physics_frame
	check(toad.defeated and toad._blocker.disabled and save.has_completed(TOAD.DEFEATED),
		"victory opens the physical passage and saves the world fact")
	player.set_physics_process(true)
	player.reset_after_map_fall(STRIKE_AT)
	Input.action_press(&"ui_right")
	for i in 90: await physics_frame
	Input.action_release(&"ui_right")
	check(player.global_position.x > BLOCK_X, "real Lan movement crosses the opened passage after victory")
	level.queue_free()
	await process_frame
	level = SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	check(level.bronze_toad.defeated and level.bronze_toad._blocker.disabled,
		"reentering the map keeps the guard defeated")
	level.queue_free()
	await process_frame
	expect_save_untouched()
	finish("A25 BRONZE TOAD")


func test_hover_volley() -> void:
	player.reset_after_map_fall(FIGHT_AT)
	player.combat_stats.restore_health()
	check(toad._engage(), "fight can restart to check the hover volleys")
	toad._hover = true
	toad._wait = 10.0
	toad._release_ball()
	var hover_x := toad._ball_destination.x
	player.reset_after_map_fall(Vector2(hover_x, TOAD.ORIGIN.y))
	level.snap_camera()
	player.set_physics_process(true)
	toad.set_physics_process(true)
	for i in 55:
		await physics_frame
		if toad._hazards.size() == 3: break
	check(toad._hazards.size() == 3, "the first hover volley telegraphs three spears")
	if toad._hazards.size() == 3:
		var center: ATTACK = toad._hazards[1]
		var left: ATTACK = toad._hazards[2]
		var right: ATTACK = toad._hazards[0]
		check(toad._ball_at.y < player.position.y - 310.0 \
			and center.endpoint.x - left.endpoint.x > 150.0 \
			and right.endpoint.x - center.endpoint.x > 150.0,
			"the raised ball fans its three lanes apart directly below it")
		await capture("13_hover_fan")
		while is_instance_valid(center) and center.age < 0.62: await physics_frame
		var health := player.combat_stats.health
		var key := InputEventKey.new()
		key.physical_keycode = KEY_K
		key.pressed = true
		Input.parse_input_event(key)
		await physics_frame
		key = InputEventKey.new()
		key.physical_keycode = KEY_K
		Input.parse_input_event(key)
		for i in 24: await physics_frame
		check(player.combat_stats.health == health and player.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS,
			"a single K parries the first release directly under the ball on Hard")
		for i in 54: await physics_frame
		check(player.combat_stats.health < health, "the following release still threatens Lan without another K")
	toad.set_physics_process(false)
	player.set_physics_process(false)
	toad.reset_attempt()

	# A forced contact at the muzzle covers the overlap case apart from ground spacing.
	player.reset_after_map_fall(FIGHT_AT)
	player.combat_stats.restore_health()
	if toad._engage():
		toad._ball_at = FIGHT_AT - Vector2(0, TOAD.BALL_HOVER_HEIGHT)
		toad._fire_hover_volley(FIGHT_AT.x)
		player.reset_after_map_fall(toad._ball_at + Vector2(0, 63.0))
		player.start_parry()
		var health := player.combat_stats.health
		var center: ATTACK = toad._hazards[1]
		var side: ATTACK = toad._hazards[0]
		center.step(center.cue + 0.01)
		side.step(side.cue + 0.01)
		check(center.impact_beat.spent and not side.settled \
			and player.combat_stats.health == health,
			"a close-range overlapping spear on the same release cannot hit after a parry")
	toad.reset_attempt()


func test_hammer_responses() -> void:
	for response in [&"water", &"jump", &"parry"]:
		player.reset_after_map_fall(FIGHT_AT)
		player.combat_stats.restore_health()
		player.facing_direction = 1.0
		check(toad._engage(), "isolated hammer fixture starts for %s" % response)
		toad._fly = response != &"water"
		toad._water_slam = not toad._fly
		toad._released = true # Use the real hammer timeline without an overlapping ball.
		toad._wait = 10.0
		toad._enter_hammer(TOAD.Hammer.LIFT)
		level.snap_camera()
		player.set_physics_process(true)
		toad.set_physics_process(true)
		var health := player.combat_stats.health
		if response == &"water":
			for i in 90:
				await physics_frame
				if not toad._hazards.is_empty(): break
			if not toad._hazards.is_empty():
				var jet: ATTACK = toad._hazards[0]
				for i in 15: await physics_frame
				check(jet.age < jet.cue and toad._warning._used > 0, "water remains visibly cued a quarter second after impact")
				await capture("14_jet_fuse")
				Input.action_press(&"ui_left")
				for i in 52: await physics_frame
				Input.action_release(&"ui_left")
				check(not jet.settled and player.global_position.x < jet.global_position.x - ATTACK.JET_WARNING_HALF_WIDTH,
					"walking after the slam leaves the water column before it lifts Lan")
			else:
				check(false, "water slam spawns its real jet")
		else:
			while toad.hammer == TOAD.Hammer.LIFT and toad._age < TOAD.FLIGHT_TELL_AT: await physics_frame
			check(toad._warning._used > 0, "the outbound path is marked before the throw")
			if response == &"jump":
				for i in 7: await physics_frame
				Input.action_press(&"jump")
				await physics_frame
				Input.action_release(&"jump")
				for i in 25: await physics_frame
				Input.action_press(&"jump")
				await physics_frame
				Input.action_release(&"jump")
				for i in 39: await physics_frame
				check(player.double_jump_used and not toad._hammer_contact.settled and player.combat_stats.health == health,
					"two real jumps from the tell clear the outbound hammer (double=%s, hp=%d)" % [
						player.double_jump_used, player.combat_stats.health])
			else:
				await capture("15_throw_tell")
				while toad.hammer == TOAD.Hammer.LIFT: await physics_frame
				Input.action_press(&"parry")
				await physics_frame
				Input.action_release(&"parry")
				for i in 13: await physics_frame
				check(toad._hammer_contact.settled and player.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS,
					"a manual K catches the outbound hammer on Hard")
				var target_x := FIGHT_AT.x - 100.0
				Input.action_press(&"ui_left")
				for i in 100:
					await physics_frame
					if player.global_position.x <= target_x: break
				Input.action_release(&"ui_left")
				for i in 90:
					await physics_frame
					if toad._hazards.size() >= 8 and toad._hazards[1].age >= toad._hazards[1].cue + ATTACK.BURST_WINDUP:
						break
				check(absf(player.global_position.x - target_x) < 36.0 and player.combat_stats.health == health,
					"Lan can move from the parry into the first rain opening before the blast")
				await capture("16_rain_opening")
				Input.action_press(&"ui_right")
				for i in 105:
					await physics_frame
					if player.global_position.x >= FIGHT_AT.x: break
				Input.action_release(&"ui_right")
				for i in 175:
					await physics_frame
					if toad.hammer == TOAD.Hammer.RECALL and toad._rig.head_at().x >= player.global_position.x - 154.0:
						break
				check(toad.hammer == TOAD.Hammer.RECALL and player.combat_stats.health == health,
					"walking from the first opening clears the remaining rain before recall")
				Input.action_press(&"parry")
				await physics_frame
				Input.action_release(&"parry")
				for i in 32: await physics_frame
				check(toad.hammer == TOAD.Hammer.REST and player.combat_stats.health == health,
					"a second K closes the full throw and recall sequence without damage")
		toad.set_physics_process(false)
		player.set_physics_process(false)
		toad.reset_attempt()


func sample_states() -> void:
	if toad.engaged:
		camera_stable = camera_stable and level.camera.zoom.is_equal_approx(Vector2.ONE) \
			and level.camera.offset.is_zero_approx()
	if toad.hammer in [TOAD.Hammer.OUTBOUND, TOAD.Hammer.FAR]:
		longest_flight = maxf(longest_flight, toad._flight_length)
	if toad.hammer == TOAD.Hammer.OUTBOUND and toad._flight_length >= 450.0:
		await capture("02_flying_hammer")
	if toad.hammer == TOAD.Hammer.RECALL:
		var floor_grip := toad._rig.floor_grip(toad._grip.x, 0.0, 0.0)
		drag_continuous = drag_continuous and toad._roll_frame == 0 and is_zero_approx(toad._angle) \
			and toad._grip.is_equal_approx(floor_grip)
		var view_center := level.camera.get_screen_center_position()
		var view_half := level.get_viewport_rect().size.x * 0.5 / level.camera.zoom.x
		if absf(toad._rig.head_at().x - view_center.x) < view_half - 52.0:
			if toad._age >= 0.06: await capture("09_ground_drag")
	if toad.ball == TOAD.Ball.ROLL: await capture("03_roll")
	if toad.ball == TOAD.Ball.HOVER: await capture("04_hover")
	if toad.ball == TOAD.Ball.CROSS: await capture("05_gold_cross")
	var airborne := 0
	var stakes := 0
	var burst_visible := false
	for hazard in toad._hazards:
		if not is_instance_valid(hazard): continue
		hazard_kinds[hazard.kind] = true
		if hazard.kind == ATTACK.Kind.STAKE:
			stakes += 1
			if hazard.age >= 0.12 and hazard.age < hazard.fall_time:
				airborne += 1
			if hazard.age >= hazard.cue + ATTACK.BURST_WINDUP and hazard.age < hazard.cue + 0.19:
				burst_visible = true
		if hazard.kind == ATTACK.Kind.BOLT and hazard.age < hazard.cue and toad._warning._used > 0:
			await capture("10_spear_lane")
		if hazard.age < hazard.cue + 0.14: continue
		if hazard.kind == ATTACK.Kind.JET: await capture("07_water_jet")
		if hazard.kind == ATTACK.Kind.SPIKE: await capture("08_ground_spear")
	most_airborne_stakes = maxi(most_airborne_stakes, airborne)
	most_live_stakes = maxi(most_live_stakes, stakes)
	if airborne >= 8: await capture("11_needle_rain")
	if burst_visible: await capture("12_needle_bursts")


func capture(name: String) -> void:
	if sampled.has(name): return
	sampled[name] = true
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
