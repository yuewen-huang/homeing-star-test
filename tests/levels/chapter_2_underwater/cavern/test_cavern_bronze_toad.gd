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
var last_slam_frame := -1000
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
	toad.slam_landed.connect(func(_at: Vector2) -> void: last_slam_frame = Engine.get_physics_frames())
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
	var impact_y := INF
	for i in 33:
		await physics_frame
		for child in toad.get_children():
			var impact := child as CombatImpactEffect
			if impact != null and impact.kind == CombatImpactEffect.Kind.NORMAL_HIT:
				impact_y = impact.global_position.y
	check(toad.combat_stats.health < guard_health, "real J input damages the guard through its front hurtbox")
	check(impact_y > TOAD.ORIGIN.y - 85.0 and impact_y < TOAD.ORIGIN.y - 12.0,
		"the grounded blade flashes at its contact instead of the mouth (y=%.1f)" % impact_y)
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
				and sampled.has("07_stone_fracture") and sampled.has("08_ground_spear") \
				and sampled.has("09_ground_drag") and sampled.has("11_needle_rain"):
			break
	check(combos.size() == 4, "all four hammer/ball combinations run through the game scene")
	check(longest_flight >= 1100.0, "the hammer travels %.1f world px on the straight throw" % longest_flight)
	check(sampled.has("09_ground_drag") and drag_continuous,
		"the hammer stays unspun and on the floor through every observed recall frame")
	check(camera_stable, "Lan stays framed at normal zoom, with offset only for the authored slam")
	check(most_airborne_stakes >= 3 and most_live_stakes == 9,
		"three fans plant nine spaced spears, with a full fan visibly airborne")
	check(sampled.has("10_spear_lane"), "a pending spear draws a full shared range strip")
	check((toad._assets["spear"][2] as Texture2D).get_width() == 144,
		"the thicker spear loads the higher-density frame")
	check(toad._sphere.radius == TOAD.BALL_RADIUS and TOAD.BALL_RADIUS >= 46.0,
		"the enlarged ball uses the corresponding contact radius")
	for kind in [ATTACK.Kind.STAKE, ATTACK.Kind.SPIKE, ATTACK.Kind.FRACTURE, ATTACK.Kind.BOLT]:
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
	toad._pose(toad._rig.floor_grip(TOAD.READY_X, 0.0, 2.0), 0.0)
	coin.age = 1.0
	ingot.age = 1.0
	coin.at = toad._rig.head_at()
	ingot.at = FIGHT_AT + Vector2(0, -40)
	toad._touch_tadpoles(toad._sphere, Transform2D(0.0, coin.at), true)
	toad._touch_tadpoles(toad._sphere, Transform2D(0.0, ingot.at), false)
	check(coin.form == TOAD.Spawn.COIN and ingot.form == TOAD.Spawn.INGOT,
		"hammer and ball contacts produce the two different forms")
	toad._flight = Vector2(-TOAD.FLIGHT_SPEED, 0)
	toad._flight_length = 0.0
	toad._rains_fired = 3
	toad._enter_hammer(TOAD.Hammer.OUTBOUND)
	toad._redirect_flight()
	var largest_step := 0.0
	for i in 10:
		var before := toad._rig.head_at()
		toad._update_flight(1.0 / 60.0)
		largest_step = maxf(largest_step, before.distance_to(toad._rig.head_at()))
	check(absf(toad._flight.y) > 0 and toad._flight.length() > TOAD.FLIGHT_SPEED and largest_step < 32.0,
		"the coin changes direction and speed continuously (largest head step %.1f px)" % largest_step)
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
	toad._spawn_ground_spike(FIGHT_AT.x, 0.55)
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
	await test_stake_pogo()
	await test_stake_fracture_chain()

	player.reset_after_map_fall(FIGHT_AT)
	check(toad._engage(), "fight restarts for victory settlement")
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
	for response in [&"fracture_stand", &"fracture_jump", &"jump", &"parry"]:
		var fracture: bool = response in [&"fracture_stand", &"fracture_jump"]
		var start := STRIKE_AT if response == &"fracture_jump" else FIGHT_AT
		if response == &"parry": start.x += 70.0 # Clear of the first fan, still on the hammer path.
		player.reset_after_map_fall(start)
		player.combat_stats.restore_health()
		player.facing_direction = 1.0
		check(toad._engage(), "isolated hammer fixture starts for %s" % response)
		toad._fly = not fracture
		toad._fracture_slam = fracture
		toad._released = true # Use the real hammer timeline without an overlapping ball.
		toad._wait = 10.0
		toad._enter_hammer(TOAD.Hammer.LIFT)
		level.snap_camera()
		player.set_physics_process(true)
		toad.set_physics_process(true)
		var health := player.combat_stats.health
		if fracture:
			await check_fracture_response(response == &"fracture_jump", health)
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
				while toad.hammer == TOAD.Hammer.LIFT and toad._age < TOAD.FLIGHT_WINDUP - 0.045:
					await physics_frame
				Input.action_press(&"parry")
				await physics_frame
				Input.action_release(&"parry")
				for i in 16: await physics_frame
				check(toad._hammer_contact.settled and player.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS,
					"a manual K catches the outbound hammer on Hard")
				var saw_recall_tell := false
				for i in 300:
					await physics_frame
					if toad.hammer == TOAD.Hammer.FAR and toad._presentation.recall_strength > 0.25:
						saw_recall_tell = toad._presentation.recall_to > toad._presentation.recall_from
					if toad.hammer == TOAD.Hammer.RECALL and toad._recall_step == 2:
						break
				check(saw_recall_tell, "the ground cue shows the direction before the hammer starts dragging")
				check(toad.hammer == TOAD.Hammer.RECALL and player.combat_stats.health == health,
					"the gap beside the planted spears remains safe before recall (x=%.1f hp=%d)" % [
						player.global_position.x, player.combat_stats.health])
				Input.action_press(&"parry")
				await physics_frame
				Input.action_release(&"parry")
				for i in 32: await physics_frame
				check(toad.hammer == TOAD.Hammer.REST and toad._hammer_contact.settled \
					and player.combat_stats.health == health,
					"a second K closes the full throw and recall sequence without damage")
		toad.set_physics_process(false)
		player.set_physics_process(false)
		toad.reset_attempt()


func test_stake_pogo() -> void:
	player.reset_after_map_fall(FIGHT_AT)
	player.combat_stats.restore_health()
	check(toad._engage(), "fight can restart to check planted spear contacts")
	var head := FIGHT_AT + Vector2(42, -145)
	toad._sling_spear_rain(head)
	toad._sling_spear_rain(head - Vector2(340, 0))
	var spears: Array[ATTACK] = toad._hazards.duplicate()
	var left := spears[0]
	var middle := spears[1]
	var next_group := spears[5]
	check(is_equal_approx(middle.endpoint.x - left.endpoint.x, 82.0) \
		and is_equal_approx(left.endpoint.x - next_group.endpoint.x, 176.0),
		"the two close hops and the gap to the next group have distinct spacing")
	player.reset_after_map_fall(left.endpoint)
	var health := player.combat_stats.health
	await step_stakes(spears, 28)
	check(player.combat_stats.health == health - 16 and left.is_planted_stake(),
		"a standing player gets hit as the spear plants and the spear remains")
	await step_stakes(spears, 45)
	check(player.combat_stats.health == health - 32,
		"staying in the same planted spear rearms contact after recoil time")
	player.reset_after_map_fall(middle.endpoint + Vector2(41, 0))
	player.combat_stats.restore_health()
	player.combat_stats.restore_stamina(player.combat_stats.max_stamina)
	player.set_physics_process(true)
	await physics_frame
	Input.action_press(&"jump")
	await step_stakes(spears, 1)
	Input.action_release(&"jump")
	await step_stakes(spears, 15)
	Input.action_press(&"jump")
	await step_stakes(spears, 1)
	Input.action_release(&"jump")
	await steer_to_spear(spears, middle, 34.0)
	var first_offset := absf(player.global_position.x - middle.endpoint.x)
	check(player.double_jump_used, "real jumps spend the second jump before the first spear")
	await downslash_spear(spears)
	check(first_offset >= 30.0 and player.fast_fall.last_contacts == 1 and player.velocity.y < 0.0 \
		and not player.double_jump_used and player.combat_stats.health == health,
		"early downslash from %.1f px off-centre rebounds and restores the second jump" % first_offset)
	await capture("16_spear_pogo")
	await steer_to_spear(spears, left, 22.0)
	check(left._stake_ready_for_downslash() and not next_group._stake_ready_for_downslash(),
		"only the aligned spear tip lights up within the short hop")
	await capture("16a_spear_tip_alignment")
	await step_stakes(spears, 6)
	await downslash_spear(spears)
	check(player.fast_fall.last_contacts == 1 and player.velocity.y < 0.0 \
		and not player.double_jump_used and player.combat_stats.health == health,
		"the short rebound allows a 100 ms wait after alignment and needs no second jump (at=%s hp=%d)" % [
			player.global_position, player.combat_stats.health])
	Input.action_press(&"ui_left")
	await step_stakes(spears, 18)
	Input.action_press(&"jump")
	await step_stakes(spears, 3)
	Input.action_release(&"jump")
	check(player.double_jump_used and player.air_state == LanPlayer.AirState.DOUBLE_JUMPING,
		"the refunded second jump works in the air")
	await steer_to_spear(spears, next_group, 22.0)
	await downslash_spear(spears)
	check(player.fast_fall.last_contacts == 1 and player.velocity.y < 0.0 \
		and not player.double_jump_used and player.combat_stats.health == health,
		"a delayed second jump crosses to the next group and chains another bounce (at=%s hp=%d)" % [
			player.global_position, player.combat_stats.health])
	player.set_physics_process(false)
	toad.reset_attempt()
	await process_frame
	check(not get_nodes_in_group(&"pogo_target").any(func(node: Node) -> bool: return toad.is_ancestor_of(node)),
		"retry clears the toad's planted spear probes")


func step_stakes(spears: Array[ATTACK], frames: int) -> void:
	for i in frames:
		await physics_frame
		for spear in spears: spear.step(1.0 / 60.0)


func steer_to_spear(spears: Array[ATTACK], target: ATTACK, lead: float) -> void:
	var side := signf(target.endpoint.x - player.global_position.x)
	var action := &"ui_left" if side < 0.0 else &"ui_right"
	Input.action_press(action)
	for i in 60:
		await step_stakes(spears, 1)
		if (target.endpoint.x - player.global_position.x) * side <= lead: break
	Input.action_release(action)


func downslash_spear(spears: Array[ATTACK]) -> void:
	Input.action_press(&"fast_fall")
	await step_stakes(spears, 2)
	Input.action_release(&"fast_fall")
	for i in 25:
		await step_stakes(spears, 1)
		if player.fast_fall.last_contacts == 1 and player.velocity.y < 0.0: break


func test_stake_fracture_chain() -> void:
	player.reset_after_map_fall(STRIKE_AT)
	player.combat_stats.restore_health()
	check(toad._engage(), "fight can restart for a continuous throw-to-slam sequence")
	toad._bag.assign([3, 0])
	toad._fracture_next = true
	toad.set_physics_process(true)
	var saw_full_fan := false
	var tossed: ATTACK
	for i in 590:
		await physics_frame
		var planted := 0
		for hazard in toad._hazards:
			if not is_instance_valid(hazard) or hazard.is_queued_for_deletion(): continue
			if hazard.is_planted_stake(): planted += 1
			if hazard.kind == ATTACK.Kind.TOSSED_STAKE: tossed = hazard
		saw_full_fan = saw_full_fan or planted == 9
		if is_instance_valid(tossed):
			check(planted > 0 and tossed.global_position.y < tossed.endpoint.y + ATTACK.STAKE_CENTER.y \
				and not is_instance_valid(tossed._stake_tip),
				"the live soil wave lifts only the spears it reaches and removes their pogo probes")
			break
	check(saw_full_fan and is_instance_valid(tossed),
		"normal AI starts the next slam while the complete throw can still be swept up")
	toad.set_physics_process(false)
	if is_instance_valid(tossed):
		player.reset_after_map_fall(tossed.global_position + Vector2(0, 29))
		player.combat_stats.restore_health()
		var health := player.combat_stats.health
		var y := player.global_position.y
		tossed.step(1.0 / 60.0)
		tossed.step(1.0 / 60.0)
		check(player.combat_stats.health == health - 12 and is_equal_approx(player.global_position.y, y),
			"the airborne spear applies one separate hit without snapping Lan to the floor (hp=%d)" % player.combat_stats.health)
		var lifted := {tossed.endpoint.x: true}
		player.reset_after_map_fall(STRIKE_AT)
		toad.set_physics_process(true)
		for i in 110:
			await physics_frame
			for hazard in toad._hazards:
				if is_instance_valid(hazard) and hazard.kind == ATTACK.Kind.TOSSED_STAKE:
					lifted[hazard.endpoint.x] = true
			if i == 9: await capture("17_tossed_spears")
			if lifted.size() == 9: break
		check(lifted.size() == 9, "all nine spears last long enough to meet the next wave (lifted=%d)" % lifted.size())
	toad.set_physics_process(false)
	toad.reset_attempt()


func check_fracture_response(jump: bool, health: int) -> void:
	for i in 90:
		await physics_frame
		if toad._hazards.size() == 2: break
	if toad._hazards.size() != 2:
		check(false, "a real hammer slam starts two fracture waves")
		return
	var west := toad._hazards[0]
	var east := toad._hazards[1]
	check(west.kind == ATTACK.Kind.FRACTURE and east.kind == ATTACK.Kind.FRACTURE \
		and west.direction.x < 0 and east.direction.x > 0 and west.impact_beat == east.impact_beat,
		"both low waves start at the actual hammer contact and share one damage beat")
	for arm: ATTACK in [west, east]:
		var visual := arm._fracture_wave
		var edge := Vector2(visual.extent(), 0)
		check(is_equal_approx(visual.to_global(-edge).x, arm.from.x) \
			and is_equal_approx(visual.to_global(edge).x, arm.endpoint.x) \
			and is_equal_approx(visual.arrival(edge), arm.from.distance_to(arm.endpoint) / ATTACK.FRACTURE_SPEED) \
			and not visual.visible and arm._fracture_tell.visible,
			"Studio front follows the true arm extent and release clock on side %.0f" % arm.direction.x)
	var wave := west if player.global_position.x < east.from.x else east
	var start_y := player.position.y
	var shook := false
	var dripped := false
	for i in 17:
		await physics_frame
		shook = shook or not level.camera.offset.is_zero_approx()
		dripped = dripped or level.drips.drops.any(func(drop: Dictionary) -> bool: return drop.tremor)
	check(shook and level.camera.offset.is_zero_approx() and dripped and wave.age < wave.cue \
		and player.combat_stats.health == health and is_equal_approx(player.position.y, start_y),
		"impact shake settles and ceiling drips fall during the harmless tell (shake=%s drips=%s)" % [shook, dripped])
	await capture("14_stone_fracture_tell")
	var arrival := wave.cue + absf(player.global_position.x - wave.from.x) / ATTACK.FRACTURE_SPEED
	for i in 60:
		if wave.age >= arrival - 0.14: break
		await physics_frame
	if jump:
		Input.action_press(&"jump")
		await physics_frame
		Input.action_release(&"jump")
	var highest := start_y
	for i in 22:
		await physics_frame
		highest = minf(highest, player.position.y)
	if jump:
		check(highest < start_y - ATTACK.FRACTURE_HEIGHT and player.combat_stats.health == health,
			"one normal jump after the tell clears the passing ground wave")
	else:
		check(player.combat_stats.health == health - 16 and is_equal_approx(highest, start_y),
			"standing in the rock wave deals one hit without launching Lan")


func sample_states() -> void:
	if toad.engaged:
		var allowed_offset := Engine.get_physics_frames() - last_slam_frame <= 20 \
			and level.camera.offset.length() < 4.3
		camera_stable = camera_stable and level.camera.zoom.is_equal_approx(Vector2.ONE) \
			and (level.camera.offset.is_zero_approx() or allowed_offset)
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
	var planted_visible := false
	for hazard in toad._hazards:
		if not is_instance_valid(hazard): continue
		hazard_kinds[hazard.kind] = true
		if hazard.kind == ATTACK.Kind.STAKE:
			if hazard.is_planted_stake(): stakes += 1
			if hazard.age >= 0.12 and hazard.age < hazard.fall_time:
				airborne += 1
			planted_visible = planted_visible or hazard.is_planted_stake()
		if hazard.kind == ATTACK.Kind.BOLT and hazard.age < hazard.cue and toad._warning._used > 0:
			await capture("10_spear_lane")
		if hazard.age < hazard.cue + 0.14: continue
		if hazard.kind == ATTACK.Kind.FRACTURE: await capture("07_stone_fracture")
		if hazard.kind == ATTACK.Kind.SPIKE: await capture("08_ground_spear")
	most_airborne_stakes = maxi(most_airborne_stakes, airborne)
	most_live_stakes = maxi(most_live_stakes, stakes)
	if airborne >= 3: await capture("11_needle_rain")
	if planted_visible: await capture("12_planted_spears")


func capture(name: String) -> void:
	if sampled.has(name): return
	sampled[name] = true
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
