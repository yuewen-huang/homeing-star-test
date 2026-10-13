extends SceneTree

var room
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print("OK " if value else "FAIL ", message)

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale / 60
		room.adapter.deer._physics_process(delta)
		room._physics_process(delta)
		room.adapter.deer.vfx._process(delta)

func check_hits(damages: Array, frames: Array, prefix: String) -> void:
	check(room.dummy.contacts.size() == damages.size(), prefix + " has the correct number of hits")
	if room.dummy.contacts.size() != damages.size(): return
	var keys: Array = []
	var last_time := -1.0
	for i in damages.size():
		var hit: Dictionary = room.dummy.contacts[i]
		check(hit.damage == damages[i] and hit.first_frame == frames[i], prefix + " knife %d uses real landing frame and damage" % (i + 1))
		check(not keys.has(hit.key) and hit.first_time > last_time, prefix + " knife %d has a unique ID and cumulative time" % (i + 1))
		keys.append(hit.key)
		last_time = hit.first_time

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	check(room.combo_picker.item_count == 5, "Development picker exposes the four phase mappings plus the vine duel")
	var ids := [&"fast_slow", &"fast_fast_slow"]
	var damage_sets := [[12, 20], [12, 12, 20]]
	var frame_sets := [[1, 0], [1, 1, 0]]
	for index in 2:
		room.select_combo(index)
		room.play_action(2)
		check(deer.combo_id == ids[index] and deer.phase == index + 1, "Phase %d selects its combo; completed manual root combat is enabled" % (index + 1))
		tick(500)
		check_hits(damage_sets[index], frame_sets[index], "Phase %d" % (index + 1))
		check(deer.state == DeerBoss.State.IDLE and deer.combo_step == -1 and deer.attack_hitbox.attack == null, "Phase %d returns to manual idle with closed damage" % (index + 1))
		check(deer.vfx._waves.is_empty() and painted("heavy_stomp").is_empty() and painted("light_stomp").is_empty(), "Phase %d has no waves or lingering mist" % (index + 1))
		if index == 1:
			check(room.dummy.contacts[1].first_time < 1 and room.dummy.contacts[2].first_time > 3, "Fast-fast-slow has two fast contacts before its delayed finisher")
	# Phase 3 uses its real near-range actions, sampled by the same dummy.
	room.select_combo(2)
	check(deer.phase == 3, "Phase 3 entry still selects the third phase")
	room.dummy.begin_action()
	room.play_action(2)
	tick(500)
	check(deer.clash_phase.action_id == &"three_cuts" and room.dummy.contacts.size() == 3 and deer.attack_hitbox.attack == null, "Phase 3 uses three independent near-range contacts and closes damage")
	check(deer.start_phase_combo() and deer.state == DeerBoss.State.CLASH, "Production action entry shares the real phase 3 combo")
	deer.phase = 1
	check(deer.start_phase_combo() and deer.combo_id == &"fast_slow", "Production entry maps the current phase to its prepared combo")
	check(not deer.start_phase_combo(5) and deer.combo_id == &"fast_slow", "Invalid phase cannot replace an active combo")
	room.select_combo(3)
	var seen: Array = []
	var last_tail := -1
	var repeats := 0
	var valid_repeats := true
	for attempt in 40:
		room.play_action(2)
		if attempt == 0:
			check(deer.combo_id == &"adaptive" and deer._adaptive_tail == -1, "Fourth-phase tail is undecided at the shared opening")
			tick(20)
			check(deer._adaptive_tail == -1 and room.dummy.contacts.size() == 1, "First knife lands before branch selection")
			tick(15)
		else:
			tick(35)
		var tail: int = deer._adaptive_tail
		if not seen.has(tail):
			seen.append(tail)
			tick(465)
			check_hits([12, 12, 20] if tail == 0 else [12, 20, 12], [1, 1, 0] if tail == 0 else [1, 0, 1], "Adaptive tail %d" % tail)
			check(deer.combo_step == -1 and deer.attack_hitbox.attack == null, "Adaptive tail %d completes and closes damage" % tail)
		repeats = repeats + 1 if tail == last_tail else 1
		valid_repeats = valid_repeats and repeats <= 2
		last_tail = tail
	check(seen.has(0) and seen.has(1), "Fourth phase exercises both fast and slow continuations")
	check(valid_repeats, "Fourth phase never repeats the same tail three times")
	room.play_action(2)
	tick(20)
	deer.enter_stagger(2)
	tick(120)
	check(deer.combo_step == -1 and room.dummy.contacts.size() == 1, "Stagger before branching cancels both possible continuations")
	room.select_combo(1)
	room.set_playback_speed(0)
	room.play_action(2)
	tick(2000)
	check_hits([12, 12, 20], [1, 1, 0], "Quarter-speed phase 2")
	room.set_playback_speed(2)
	current_scene = null
	room.free()
	print("PHASE COMBOS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func painted(kind: String) -> Array:
	return room.adapter.deer.vfx._painted.filter(func(effect: DeerPaintedEffect) -> bool: return effect.kind == kind)
