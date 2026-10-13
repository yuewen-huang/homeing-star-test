extends SceneTree
## Wind-phase combo library on the development dummy: contact order, damage,
## danger type, rhythm, crossover facing, charge stop, branches, slow motion,
## interruption and clean recovery. Design: docs/design/chapter_1_deer_wind_combos.md.

const NORMAL := CombatAttackData.DangerType.NORMAL
const RED := CombatAttackData.DangerType.COUNTERABLE_DANGER
const GOLD := CombatAttackData.DangerType.UNPARRYABLE_DANGER

var room
var deer: DeerBoss
var checks := 0
var failures := 0
var dangers: Array = []
var clips_seen: Array = []
var last_branch := -1

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale / 60.0
		var before: int = room.dummy.contacts.size()
		deer._physics_process(delta)
		room._physics_process(delta)
		deer.vfx._process(delta)
		if room.dummy.contacts.size() > before:
			dangers.append(deer.attack_hitbox.attack.danger_type if deer.attack_hitbox.attack != null else -1)
		var clip := String(deer.animated_sprite.animation)
		if clips_seen.is_empty() or clips_seen.back() != clip: clips_seen.append(clip)
		if deer.clash_phase.branch >= 0: last_branch = deer.clash_phase.branch

## Plays library entry `id` at dummy x until the deer is idle again (or `limit` ticks).
func play(id: StringName, dummy_x: float, limit := 900) -> int:
	room.dummy_x.value = dummy_x
	room.select_combo_library(DeerClashPhase.LIBRARY.find(id))
	dangers.clear()
	clips_seen.clear()
	last_branch = -1
	room.play_action(4)
	var ticks := 0
	while ticks < limit:
		tick(1)
		ticks += 1
		if deer.state == DeerBoss.State.IDLE and ticks > 10: break
	print("CONTACTS %s %s %s" % [id, JSON.stringify(contact_clips()), JSON.stringify(contact_times())])
	return ticks

func contact_clips() -> Array:
	return room.dummy.contacts.map(func(hit: Dictionary) -> String: return hit.clip)

func contact_damage() -> Array:
	return room.dummy.contacts.map(func(hit: Dictionary) -> int: return hit.damage)

func contact_times() -> Array:
	return room.dummy.contacts.map(func(hit: Dictionary) -> float: return hit.first_time)

func clean_finish(label: String) -> void:
	check(deer.state == DeerBoss.State.IDLE and deer.attack_hitbox.attack == null, "%s returns to idle with damage closed" % label)

func run() -> void:
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	seed(20261012)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	deer = room.adapter.deer; deer.set_physics_process(false); deer.vfx.set_process(false)
	room.select_combo(2)
	check(room.library_picker.visible and room.library_picker.item_count == DeerClashPhase.LIBRARY.size(), "Wind phase shows the combo library picker with every combo")
	check(room.adapter.action_names()[4].contains(DeerClashPhase.COMBOS[DeerClashPhase.LIBRARY[0]].label), "Key 5 defaults to the existing pressure combo")

	# Probe three: thrust, low-linked sweep, held lift; fast, fast, slow.
	play(&"probe_three", 688)
	check(contact_clips() == ["thrust_ING", "flick_sweep_ING", "flick_lift_ING"], "Probe three hits with thrust, sweep and lift in order")
	check(contact_damage() == [12, 12, 14] and dangers == [NORMAL, NORMAL, NORMAL], "Probe three is three ordinary parryable contacts")
	var t := contact_times()
	if t.size() == 3:
		check(t[1] - t[0] < t[2] - t[1], "Probe three speeds up then waits: second gap is longer (%.2f / %.2f)" % [t[1] - t[0], t[2] - t[1]])
	var between := clips_seen.slice(clips_seen.find("thrust_ING"), clips_seen.find("flick_sweep_ING"))
	check(not between.has("thrust_END") and not between.has("flick_START"), "Thrust links low into the sweep without rising and bowing again")
	clean_finish("Probe three")

	# Delayed gore: thrust, held rear-up, red strike.
	var red_seen_before_strike := false
	room.dummy_x.value = 688
	room.select_combo_library(DeerClashPhase.LIBRARY.find(&"delayed_gore"))
	dangers.clear(); clips_seen.clear()
	room.play_action(4)
	for i in 600:
		tick(1)
		if room.dummy.contacts.size() == 1 and deer.vfx.red_warning.visible: red_seen_before_strike = true
		if deer.state == DeerBoss.State.IDLE and i > 10: break
	check(contact_clips() == ["thrust_ING", "rear_gore_ING"] and dangers == [NORMAL, RED], "Delayed gore ends with one red rear gore after an ordinary thrust")
	t = contact_times()
	if t.size() == 2: check(t[1] - t[0] > 1.8, "Delayed gore holds the rear-up before striking (gap %.2f s)" % (t[1] - t[0]))
	check(red_seen_before_strike, "Red flash appears during the hold, before the red strike")
	clean_finish("Delayed gore")

	# Crossover: thrust, leap over the dummy, thrust back from the other side.
	play(&"crossover", 688)
	check(contact_clips() == ["thrust_ING", "thrust_ING"] and dangers == [NORMAL, NORMAL], "Crossover hits the same dummy before and after the leap")
	check(deer.position.x < 688 and deer.direction > 0, "Leap lands beyond the dummy and turns back to face it (x=%.0f, dir=%.0f)" % [deer.position.x, deer.direction])
	check(clips_seen.has("leap_turn_ING") and clips_seen.has("leap_turn_END"), "Crossover plays the authored leap and turn")
	clean_finish("Crossover")

	# Sweep charge: from far away the sweep whiffs, the gold charge stops short and the uppercut connects.
	play(&"sweep_charge", 400)
	check(dangers.size() >= 1 and dangers.all(func(d: int) -> bool: return d == GOLD), "Charge contacts are all gold, unparryable")
	check(contact_clips().has("uppercut_ING"), "Charge ends in a connecting uppercut")
	check(deer.position.x >= 400 + DeerClashPhase.CHARGE_STOP_DISTANCE - 1.0, "Charge stops in front of the dummy instead of passing it (x=%.0f)" % deer.position.x)
	check(clips_seen.has("charge_run_ING") and clips_seen.has("thrust_END"), "Sweep rises before the gold charge run")
	clean_finish("Sweep charge")
	play(&"sweep_charge", 688)
	check(contact_clips().size() >= 1 and contact_clips()[0] == "flick_sweep_ING" and dangers[0] == NORMAL, "At close range the sweep itself lands as an ordinary hit")

	# Branch opener: both branches appear, never three of the same in a row.
	var picks: Array = []
	for i in 8:
		play(&"branch_opener", 688)
		picks.append(last_branch)
		if last_branch == 0:
			check(contact_clips() == ["thrust_ING", "flick_sweep_ING", "flick_lift_ING"], "Branch A continues low into sweep and lift")
		else:
			check(contact_clips() == ["thrust_ING", "heavy_ING"] and dangers == [NORMAL, RED], "Branch B rises, leaps and finishes with a red stomp")
	check(picks.has(0) and picks.has(1), "Both branches appear across eight openings %s" % str(picks))
	var longest := 1
	var run_length := 1
	for i in range(1, picks.size()):
		run_length = run_length + 1 if picks[i] == picks[i - 1] else 1
		longest = maxi(longest, run_length)
	check(longest <= 2, "No branch repeats more than twice in a row")

	# Quarter speed keeps the same contacts and action-time rhythm.
	play(&"probe_three", 688)
	var normal_times := contact_times()
	room.set_playback_speed(0)
	play(&"probe_three", 688, 3600)
	var slow_times := contact_times()
	room.set_playback_speed(2)
	check(slow_times.size() == normal_times.size(), "Quarter speed keeps all probe contacts")
	var same := slow_times.size() == normal_times.size()
	for i in mini(slow_times.size(), normal_times.size()):
		same = same and absf(slow_times[i] - normal_times[i]) < 0.03
	check(same, "Quarter speed keeps contact action times %s vs %s" % [str(slow_times), str(normal_times)])

	# Stagger mid-combo cancels the rest.
	room.dummy_x.value = 688
	room.select_combo_library(DeerClashPhase.LIBRARY.find(&"probe_three"))
	room.play_action(4); tick(40)
	var contacts_at_stagger: int = room.dummy.contacts.size()
	deer.enter_stagger(2.0); tick(200)
	check(room.dummy.contacts.size() == contacts_at_stagger and deer.clash_phase.steps.is_empty() and deer.attack_hitbox.attack == null, "Stagger cancels the remaining probe steps")

	var after := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	check(after == saved, "Combo previews leave saved progress unchanged")
	print("WIND COMBO LIBRARY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
