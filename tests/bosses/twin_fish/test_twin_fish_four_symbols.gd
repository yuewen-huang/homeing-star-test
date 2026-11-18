extends "test_twin_fish_lightning.gd"

func verify_opening() -> void:
	var encounter := level.twin_fish_encounter
	if not OS.is_debug_build():
		encounter.opening_movement = Duel.Movement.FOUR_SYMBOLS
	walk(100.0)
	for frame in 150:
		await physics_frame
		if encounter.engaged: break
	walk(0)
	if OS.is_debug_build(): press_debug_phase_key(KEY_2)
	var seeded := false
	for frame in 800:
		await physics_frame
		if not seeded and is_instance_valid(encounter.fish):
			encounter.fish._swim_random.seed = 41019
			seeded = true
		if encounter.battle_ready: break
	check(encounter.battle_ready, "The independent A27 entry opens with real player controls")
	if not encounter.battle_ready:
		finish("A27 FOUR SYMBOLS")
		return

	var fish := encounter.fish
	var duel := fish.lightning
	var progress_bar := fish._taichi_array._conversion_bar
	check(duel.movement == Duel.Movement.FOUR_SYMBOLS and is_equal_approx(fish._taichi_array.stage, 3.0)
		and duel.clashes == 0, "The four-symbol entry starts at its first speed pair")
	check(is_instance_valid(progress_bar) and progress_bar.is_visible_in_tree()
		and progress_bar.max_value == 5.0 and progress_bar.value == 0.0, "Four Symbols starts with a visible empty five-step bar")
	var first_pursuit := 0.0
	var first_dash := 0.0
	var observed_punish := false
	var lightning_matches := true
	var shot_during_lock := false
	var launched_at_lan := false
	var next_pursuit := 0.0
	var speed_while_flying := 0.0
	for frame in 2400:
		await physics_frame
		lightning_matches = lightning_matches and (duel.yang.visible == duel.can_clash())
		if duel.clashes > 0 and duel.orb.flying:
			if next_pursuit == 0.0: next_pursuit = duel.orb.pursuit_speed
			if duel.orb.age >= 0.10:
				speed_while_flying = duel.orb.pursuit_speed
				break
			continue
		if duel.orb.flying: first_pursuit = duel.orb.pursuit_speed
		if duel.orb.flying and duel.beat == Duel.Beat.LOCK: shot_during_lock = true
		if duel.orb.flying and duel.orb.age < 0.02:
			var toward := duel.orb.position.direction_to(duel._target())
			launched_at_lan = launched_at_lan or (duel.orb.velocity.normalized().dot(toward) > 0.999
				and is_equal_approx(duel.orb.velocity.length(), 235.0))
		if duel.beat == Duel.Beat.DASH: first_dash = maxf(first_dash, fish.white_swimmer.speed)
		var x := duel._target().x
		match duel.beat:
			Duel.Beat.SWIM, Duel.Beat.CAST, Duel.Beat.LURE, Duel.Beat.AIM: walk(-320.0 - x)
			Duel.Beat.LOCK:
				walk((-365.0 if duel.orb.flying and duel.orb.age >= 0.15 else -320.0) - x)
			Duel.Beat.OPEN:
				observed_punish = not fish.invulnerable and not duel.orb.flying
				walk(0.0)
			_: walk(0.0)
	walk(0.0)
	check(is_equal_approx(first_pursuit, 150.0) and is_equal_approx(first_dash, 750.0), "The first four-symbol exchange uses the starting speed pair")
	check(lightning_matches and shot_during_lock, "The gold lightning follows the clash window and the orb can launch during aim")
	check(launched_at_lan, "The first orb launches at 235 px/s directly toward Lan")
	check(observed_punish and duel.clashes == 1 and progress_bar.value == 1.0,
		"A real clash opens the punish window and fills one progress segment")
	check(is_equal_approx(next_pursuit, 230.0) and is_equal_approx(speed_while_flying, next_pursuit)
		and is_equal_approx(duel._four_dash_speed(), 650.0), "The next exchange keeps the new speed pair throughout its attacks")
	check_conversion_speed_steps(duel)
	check(duel.sea.charge == Vector2i.ZERO and duel.sea.armed < 0 and is_equal_approx(fish._taichi_array.stage, 3.0),
		"The preview remains in the four-symbol array")
	check_swept_orb_contact(duel)
	check_paired_orb_contact(duel)
	check_orb_steering(duel)
	if OS.is_debug_build():
		await verify_debug_phase_switches(encounter)
		duel = fish.lightning
	encounter.reset_attempt()
	await wait_frames(3)
	check(not is_instance_valid(duel), "Retry retires the old four-symbol controller and orb")
	expect_save_untouched()
	finish("A27 FOUR SYMBOLS")

func check_conversion_speed_steps(duel: Duel) -> void:
	var previous := duel.clashes
	var expected := true
	for count in range(7):
		duel.clashes = count
		var step := mini(count, 5)
		expected = expected and is_equal_approx(duel._four_orb_speed(), 150.0 + 80.0 * step)
		expected = expected and is_equal_approx(duel._four_dash_speed(), 750.0 - 100.0 * step)
	duel.clashes = previous
	check(expected, "Five clashes linearly reach and hold the final 550/250 speed pair")

func check_swept_orb_contact(duel: Duel) -> void:
	var sprite := duel.fish.white_sprite
	var tail := sprite.joint_in_boss(3)
	var normal := sprite.head_in_boss().direction_to(tail).orthogonal()
	var orb_at := duel.orb.position
	duel.orb.position = tail + normal * 140.0
	var clear := not duel._orb_clash_contact(duel.orb.position).is_finite()
	var crossed := duel._orb_clash_contact(tail - normal * 140.0).is_finite()
	duel.orb.position = orb_at
	check(clear and crossed, "A crossing orb contacts the painted fish body between motion samples")

func check_paired_orb_contact(duel: Duel) -> void:
	# Hold the overlap to isolate repeat damage from projectile steering and knockback.
	var orb := duel.orb
	var at := duel._target()
	var hp := level.player.combat_stats.health
	orb.release(at, Vector2.ZERO, duel.cast_number, orb.pursuit_speed, true)
	orb.resolve_contact()
	var first_hp := level.player.combat_stats.health
	orb.advance(orb.PAIRED_HIT_INTERVAL * 0.5, at)
	orb.resolve_contact()
	var during_interval := level.player.combat_stats.health
	orb.advance(orb.PAIRED_HIT_INTERVAL * 0.5 + 0.01, at)
	orb.resolve_contact()
	check(orb.flying and orb.paired_with_dash and first_hp < hp and during_interval == first_hp
		and level.player.combat_stats.health < during_interval, "Paired orb stays active and pulses only after its damage interval")

func check_orb_steering(duel: Duel) -> void:
	var orb := duel.orb
	var origin := orb.position
	var step := TwinFishBoss.PATH_STEP
	for speed: float in [250.0, 400.0, 550.0]:
		orb.release(origin, Vector2.RIGHT * speed, duel.cast_number, speed, true)
		orb.motion = orb.Motion.SEEKING
		var furthest := 0.0
		for frame in 120:
			orb.advance(step, origin + Vector2.LEFT * 180.0)
			furthest = maxf(furthest, orb.position.x - origin.x)
			if orb.velocity.x < 0.0: break
		check(orb.velocity.x < 0.0 and furthest < 75.0,
			"At %.0f px/s, orb turns back within %.1f px" % [speed, furthest])
	orb.release(origin, Vector2.RIGHT * 550.0, duel.cast_number, 550.0, true)
	orb.motion = orb.Motion.SEEKING
	for frame in 12:
		orb.advance(step, origin + Vector2(600.0, 600.0))
	check(orb.velocity.y > 35.0, "Fast orb bends toward a moving target without waiting to coast")
	orb.retire()

func verify_debug_phase_switches(encounter: CavernTwinFishEncounter) -> void:
	var fish := encounter.fish
	var duel := fish.lightning
	var hp := level.player.combat_stats.health
	var fish_hp := fish.combat_stats.health
	press_debug_phase_key(KEY_1)
	await wait_frames(3)
	check(not is_instance_valid(duel) and fish.lightning.movement == Duel.Movement.LIANGYI
		and fish._taichi_array.visible and not fish.lightning._preview_only,
		"Alt+1 clears the Four Symbols attack and starts Liangyi with real collisions")
	duel = fish.lightning
	press_debug_phase_key(KEY_2)
	await wait_frames(3)
	check(not is_instance_valid(duel) and fish.lightning.movement == Duel.Movement.FOUR_SYMBOLS
		and is_equal_approx(fish._taichi_array.stage, 3.0) and not fish.lightning._preview_only,
		"Alt+2 restarts Four Symbols without replaying the arrival")
	check(encounter.battle_ready and encounter.engaged and level.player.combat_stats.health == hp
		and fish.combat_stats.health == fish_hp, "Phase switching keeps the live arena and current health")

func press_debug_phase_key(code: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.alt_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var release := key.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
