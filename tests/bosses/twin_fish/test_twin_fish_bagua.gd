extends "test_twin_fish_lightning.gd"

const Bagua := Duel.Bagua

func verify_opening() -> void:
	var encounter := level.twin_fish_encounter
	var mixed := "--mixed" in OS.get_cmdline_user_args()
	encounter.opening_movement = Duel.Movement.BAGUA if mixed else Duel.Movement.FOUR_SYMBOLS
	encounter.begin()
	for frame in 800:
		await physics_frame
		if encounter.battle_ready: break
	var duel := encounter.fish.lightning
	var painting := encounter.fish._taichi_array._circle
	# Isolate the final successful exchange, including the whole existing punish window.
	if not mixed:
		duel.clashes = duel.FOUR_CONVERSION_CLASHES
		duel._clash(encounter.fish.white_sprite.head_in_boss())
		await physics_frame
		check(not duel.bagua and not encounter.fish.invulnerable, "The final Four Symbols opening remains playable")
	for frame in 350:
		await physics_frame
		if duel.bagua: break
	var array := duel.bagua
	check(array != null and array.ink == painting, "Four Symbols unfolds the same ink painting into Eight Gates")
	if array == null:
		finish("A27 BAGUA")
		return
	if mixed:
		await verify_mixed(array)
		return
	# Aiming from beyond the destination lets a projectile cross the gate before Lan.
	var saw_earth := false
	for frame in 1650:
		await physics_frame
		var destination := array.gate_at(array.LI).x - 95 if array.broken.is_empty() else array.gate_at(array.KAN).x + 95
		walk(destination - duel._target().x)
		if array.state == Bagua.State.EARTH_AIM and not saw_earth:
			saw_earth = true
			await capture("01_earth")
		if array.state == Bagua.State.CORE: break
	walk(0)
	check(saw_earth and array.broken.size() == 2 and array.state == Bagua.State.CORE, "Walking guides water through Li and earth through Kan")
	if array.state != Bagua.State.CORE:
		print("gate trace ", array.state, " broken=",array.broken," at=",duel._target()," turn=",array.black_cast," health=",level.player.combat_stats.health)
		finish("A27 BAGUA")
		return
	await capture("02_core")
	await strike_core(array)
	check(array.round_number == 2 and array.broken.is_empty(), "A real sword strike opens the second formation")
	if array.round_number != 2:
		finish("A27 BAGUA")
		return
	# Wait where the first neutral orb misses its water stamp, then read the visible exchange.
	for frame in 800:
		await physics_frame
		walk(-65 - duel._target().x)
		if array.shifted: break
	walk(0)
	check(array.shifted and array.state == Bagua.State.HIDE and array.broken.is_empty(), "The pair visibly changes hiding places with both gates intact")
	if array.shifted: await capture("03_swap")
	# Set up the real parry input against each emitted projectile, preserving the enemy timeline.
	var pressed := false
	var pressed_cast := -1
	for frame in 1600:
		await physics_frame
		if pressed:
			Input.action_release(&"parry")
			pressed = false
		if array.state == Bagua.State.CORE: break
		if array.state != Bagua.State.FLIGHT or pressed_cast == array.cast_number: continue
		var side := signf(duel.orb.velocity.x)
		if absf(side) < 0.1: continue
		level.player.facing_direction = -int(side)
		if absf(duel.orb.position.x - duel._target().x) < 95:
			Input.action_press(&"parry")
			pressed_cast = array.cast_number
			pressed = true
	Input.action_release(&"parry")
	check(array.state == Bagua.State.CORE and array.consecutive >= 2, "Consecutive blade parries expose the second core")
	if array.state == Bagua.State.CORE:
		await strike_core(array)
		for frame in 300:
			await physics_frame
			if encounter.cleared: break
	check(encounter.cleared and encounter.seals.is_empty(), "Two central strikes finish the fish form and release the seals")
	expect_save_untouched()
	finish("A27 BAGUA")

func strike_core(array: Bagua) -> void:
	var round_before := array.round_number
	for frame in 360:
		await physics_frame
		var offset := array.core_at().x - array.fish.lightning._target().x
		if absf(offset) > 55.0:
			walk(offset)
		else:
			walk(0)
			level.player.facing_direction = 1 if offset >= 0 else -1
			sword(frame % 24 < 2)
		if array.round_number != round_before or array.state != Bagua.State.CORE: break
	sword(false)
	walk(0)

func verify_mixed(array: Bagua) -> void:
	var duel := array.fish.lightning
	var intercepted := false
	var blocked_early := true
	for frame in 1200:
		await physics_frame
		if array.state == Bagua.State.CORE: break
		if array.broken.is_empty():
			blocked_early = blocked_early and not array.core_area.is_in_group(&"hurtbox")
			walk(array.gate_at(array.LI).x - 95 - duel._target().x)
		else:
			# Let the exposed white fish fire toward Lan, away from the earth stamp.
			walk(0)
			level.player.facing_direction = 1
			if array.state == Bagua.State.FLIGHT and not array.black_cast and not intercepted:
				if absf(duel.orb.position.x - duel._target().x) < 95:
					Input.action_press(&"parry")
					intercepted = true
			else: Input.action_release(&"parry")
	Input.action_release(&"parry")
	walk(0)
	check(blocked_early and intercepted and array.consecutive == 1 and array.state == Bagua.State.CORE,
		"One water break followed by one real blade parry exposes the sealed core")
	level.twin_fish_encounter.reset_attempt()
	for frame in 500:
		await physics_frame
		if level.twin_fish_encounter.battle_ready: break
	var fresh := level.twin_fish_encounter.fish.lightning.bagua
	check(not is_instance_valid(array) and fresh.round_number == 1 and fresh.broken.is_empty(),
		"Retry removes the exposed core and restarts the selected movement")
	expect_save_untouched()
	finish("A27 BAGUA MIXED")
