extends SceneTree
## Wind phase v0.3 batches 4–5: the leap is gone; gale dash closes to DASH_SPACING and
## thrusts; gale pull drags the player in above the usual wind cap and releases them;
## improvised combos pick 2–5 strikes one at a time (far → closer, airborne → flick,
## parry streak → disruptor, finishers end it, no strike three times running); the
## production AI uses them. Design: chapter_1_deer_wind_phase_design.md §8.

var room
var deer: DeerBoss
var clash: DeerClashPhase
var player: LanPlayer
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func tick(count: int) -> void:
	for i in count:
		deer._physics_process(1.0 / 60.0)
		room._physics_process(1.0 / 60.0)

func idle() -> void:
	for i in 900:
		if deer.state in [DeerBoss.State.IDLE, DeerBoss.State.WALK]: return
		tick(1)

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	room.select_combo(2)
	deer = room.adapter.deer; clash = deer.clash_phase; player = room.player
	deer.set_physics_process(false); deer.vfx.set_process(false)

	# The leap is gone everywhere.
	var leaps := 0
	for id in DeerClashPhase.COMBOS:
		var combo: Dictionary = DeerClashPhase.COMBOS[id]
		for chosen in combo.get("branches", [combo]):
			for step in chosen.steps: if step.move == &"leap": leaps += 1
	check(not DeerClashPhase.MOVES.has(&"leap") and not DeerClashPhase.COMBOS.has(&"crossover") and leaps == 0, "No combo or move uses the leap any more")
	check(DeerClashPhase.LIBRARY[0] == &"improv" and room.library_picker.item_count == DeerClashPhase.LIBRARY.size(), "Development library starts with the improvised combo")

	# Gale dash: from far away to DASH_SPACING in front of the target, then a parryable thrust.
	deer.position.x = 1400.0
	var target := 600.0
	deer.direction = -1.0
	clash.start(&"dash", target)
	var rush_speed := 0.0
	var hit_at := -1.0
	var last_x := deer.position.x
	for i in 240:
		tick(1)
		rush_speed = maxf(rush_speed, absf(deer.position.x - last_x) * 60.0)
		last_x = deer.position.x
		if hit_at < 0.0 and deer.attack_hitbox.attack != null: hit_at = deer.position.x
		if deer.state != DeerBoss.State.CLASH: break
	check(absf(rush_speed - DeerClashPhase.DASH_SPEED) < 120.0, "Gale dash rushes in at about %.0f px/s (peak %.0f)" % [DeerClashPhase.DASH_SPEED, rush_speed])
	check(hit_at > 0.0 and absf(hit_at - (target + DeerClashPhase.DASH_SPACING)) < 40.0, "Dash stops about %.0f px from the target and thrusts (hit at %.0f)" % [DeerClashPhase.DASH_SPACING, hit_at])
	check(DeerClashPhase.MOVES[&"dash"].hits[0].danger == &"normal", "Dash thrust is an ordinary, parryable strike")
	idle()

	# Gale pull: drags the player toward the deer above the 140 px/s cap, then releases.
	deer.position.x = 1200.0
	player.global_position = Vector2(700, player.global_position.y)
	deer.direction = -1.0
	clash.start(&"pull_in", player.global_position.x)
	tick(3)
	var pull := player.horizontal_combat_wind()
	check(pull > 140.0 and absf(pull - DeerClashPhase.PULL_SPEED) < 1.0, "Gale pull drags the player toward the deer at %.0f px/s (cap raised above 140)" % pull)
	for i in 120:
		tick(1)
		if clash.step_index >= 1: break
	tick(2)
	check(is_zero_approx(player.horizontal_combat_wind()), "The pull releases the player when the next strike starts")
	idle()
	deer.position.x = 1200.0
	player.global_position = Vector2(1200.0 - DeerGalePull.STOP_DISTANCE + 10.0, player.global_position.y)
	clash.start(&"pull_in", player.global_position.x)
	tick(3)
	check(is_zero_approx(player.horizontal_combat_wind()), "The pull lets go once the player is within %.0f px (striking range)" % DeerGalePull.STOP_DISTANCE)
	idle()

	# Too close: the deer steps back to make room before striking.
	deer.position.x = 820.0
	deer.direction = -1.0
	clash.start(&"thrust", 820.0 - 100.0)
	tick(int(DeerActionLibrary.duration(&"thrust_START", 12.0) * 60.0))
	check(deer.position.x > 820.0 + 40.0, "Pressed too close, the deer steps back before the thrust (now %.0f px away)" % (deer.position.x - 720.0))
	idle()

	# Improvised combos.
	seed(7)
	var lengths := {}
	var triples := 0
	var finisher_end := true
	var far_openers := {}
	for trial in 40:
		deer.position.x = 820.0
		deer.direction = -1.0
		var far := trial % 4 == 0
		clash.parry_streak = 0
		clash.last_result = -1
		clash.start(&"improv", 820.0 - (520.0 if far else 170.0))
		if far: far_openers[clash.steps[0].move] = true
		var guard := 0
		while deer.state == DeerBoss.State.CLASH and guard < 1500:
			tick(1); guard += 1
		var moves: Array = clash.beat_history.duplicate()
		lengths[moves.size()] = true
		for i in range(2, moves.size()):
			if moves[i] == moves[i - 1] and moves[i] == moves[i - 2]: triples += 1
		for i in moves.size() - 1:
			if moves[i] in DeerClashPhase.FINISHERS: finisher_end = false
		idle()
	check(far_openers.keys().all(func(m: StringName) -> bool: return m in [&"dash", &"pull", &"charge"]), "From far away the improviser opens by closing distance (%s)" % [far_openers.keys()])
	check(lengths.keys().all(func(n: int) -> bool: return n >= 1 and n <= DeerClashPhase.IMPROV_MAX_BEATS + 1) and lengths.size() >= 3, "Improvised combos vary in length %s" % [lengths.keys()])
	check(triples == 0, "No strike repeats three times in a row")
	check(finisher_end, "Red and gold strikes only ever finish a combo")
	var disrupted := 0
	for i in 200:
		clash.beats_left = 3
		clash.beat_history.clear()
		clash.parry_streak = DeerClashPhase.IMPROV_DISRUPT_STREAK
		var disrupt: Dictionary = clash._next_beat()
		if disrupt.move in [&"charge", &"heavy", &"rear_gore"] and clash.parry_streak == 0: disrupted += 1
	var rate := disrupted / 200.0
	check(absf(rate - DeerClashPhase.IMPROV_DISRUPT_CHANCE) < 0.12, "A run of %d parries brings a gold/red disruptor about %.0f%% of the time (%.0f%%), so it cannot be timed" % [DeerClashPhase.IMPROV_DISRUPT_STREAK, DeerClashPhase.IMPROV_DISRUPT_CHANCE * 100.0, rate * 100.0])
	clash.beats_left = 3
	clash._on_hit_resolved(player, CombatHitResult.Type.PARRY_SUCCESS)
	check(clash.parry_streak == 0 or deer.state == DeerBoss.State.CLASH, "Parry streak only counts during a clash")
	deer.state = DeerBoss.State.CLASH
	clash._on_hit_resolved(player, CombatHitResult.Type.PARRY_SUCCESS)
	clash._on_hit_resolved(player, CombatHitResult.Type.PARRY_SUCCESS)
	var two := clash.parry_streak
	clash._on_hit_resolved(player, CombatHitResult.Type.NORMAL_HIT)
	check(two == 2 and clash.parry_streak == 0, "Parries build the streak; any other outcome resets it")
	deer._recover(0.0)
	tick(2)

	# The production AI improvises.
	deer.manual_control = false
	deer.phase_ai.choose(150.0)
	check(deer.state == DeerBoss.State.CLASH and clash.improv, "Production AI starts an improvised combo in the wind phase")
	clash.cancel(); deer._recover(0.0)

	var after := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	check(after == saved, "Improv checks leave saved progress unchanged")
	print("WIND IMPROV: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
