extends SceneTree

class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass
	func is_ability_unlocked(_ability: StringName) -> bool: return true


## Wind-phase 拼刀 rhythms (DeerClashRhythm) on the real deer in the development room.
## Optional user args: snapshot directory, then "frames" to save every frame of each
## rhythm (subfolders r1..r4).

var room
var deer: DeerBoss
var checks := 0
var failures := 0
var output := ""
var capture_frames := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(count: int, step := 1.0 / 60.0) -> void:
	for i in count:
		var delta := step * Engine.time_scale
		deer._physics_process(delta)
		room._physics_process(delta)
		deer.vfx._process(delta)

func snapshot(path: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(path + ".png"))

func crescents() -> Array:
	return deer.clash_phase.smears.filter(func(s) -> bool: return is_instance_valid(s) and s.shape == &"crescent")

func play_rhythm(index: int) -> void:
	room.adapter.select_combo(2)
	room.adapter.library_index = index
	room.play_action(4)

func run() -> void:
	var original_progress := root.get_node("SaveProgress")
	root.remove_child(original_progress)
	original_progress.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	capture_frames = args.size() > 1 and args[1] == "frames"
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	deer = room.adapter.deer
	deer.set_physics_process(false); deer.vfx.set_process(false)

	# Data: every rhythm's fitted playback speed stays readable.
	var expected_strikes := {&"three_ding": 3, &"accel_five": 5, &"delayed_feint": 4, &"red_finale": 5}
	for id: StringName in DeerClashRhythm.ORDER:
		var rhythm := DeerClashRhythm.new(deer, id)
		var rates := rhythm.fitted_rates()
		var lo: float = rates.min()
		var hi: float = rates.max()
		check(lo >= DeerClashRhythm.MIN_FPS and hi <= DeerClashRhythm.MAX_FPS, "%s plays its clips at %.1f–%.1f fps" % [id, lo, hi])
		check(rhythm.strike_count() == expected_strikes[id], "%s has %d strikes" % [id, expected_strikes[id]])
	check(DeerClashPhase.LIBRARY == [&"improv", &"three_ding", &"accel_five", &"delayed_feint", &"red_finale"], "Library is the AI picker plus the four rhythms")

	# Each rhythm on the real deer: hit frame on the beat, damage on the beat, smear open.
	for r in DeerClashRhythm.ORDER.size():
		var id: StringName = DeerClashRhythm.ORDER[r]
		play_rhythm(r + 1)  # the dummy clears its contacts when an action starts
		var before := 0
		var rhythm: DeerClashRhythm = deer.clash_phase.rhythm
		check(rhythm != null and rhythm.id == id, "%s starts from the library" % id)
		var on_beat := true
		var open_smears := true
		var attached := true
		var restrained := true
		var palette_matches := true
		var above_floor := true
		var body_sized := true
		var opened := 0
		for strike: Dictionary in rhythm.strikes:
			while deer.clash_phase.step_time + 0.000001 < float(strike.t): tick(1)
			on_beat = on_beat and deer.animated_sprite.animation == strike.clip and absf(deer.clash_phase.step_time - float(strike.t)) <= 1.0 / 60.0 + 0.0001
			var live: Array = crescents()
			open_smears = open_smears and not live.is_empty() and live.back().age >= live.back().duration - 0.001
			attached = attached and not live.is_empty() and live.back().get_parent() == deer
			if not live.is_empty():
				var smear: PixelSlash = live.back()
				restrained = restrained and not smear.crescent_ghost and not smear.crescent_speed_lines and not smear.crescent_core
				palette_matches = palette_matches and smear.palette_key == (&"red" if strike.danger == &"red" else &"deer")
				# Include the outer echo, including enlarged final strikes. The deer origin
				# is its floor anchor; checking the whole arc catches buried lower tips.
				var outline := smear.visual_bounds()
				above_floor = above_floor and outline.end.y <= deer.global_position.y + 0.5
				var sprite := deer.animated_sprite
				var body_size := Vector2(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame).get_image().get_used_rect().size) * sprite.scale
				body_sized = body_sized and outline.size.x >= body_size.x * 1.05
				if strike.swing != "thrust": body_sized = body_sized and outline.size.y >= body_size.y * 1.05
			opened += 1 if deer.attack_hitbox.attack != null else 0
			if r == 0 and strike == rhythm.strikes[0]: await snapshot("rhythm_first_beat")
		check(on_beat, "%s: every strike's clip is on screen on its beat" % id)
		check(open_smears and attached, "%s: a crescent on the deer is fully open on every beat" % id)
		check(restrained and palette_matches, "%s: deer smears use the body palette (red danger preserved), without ghost, white core or speed lines" % id)
		check(above_floor, "%s: the full smear and outer echo stay above the floor, including finishers" % id)
		check(body_sized, "%s: every smear spans beyond the visible deer body (thrust along its long axis)" % id)
		check(opened == rhythm.strike_count(), "%s: damage opens on every beat" % id)
		tick(240)
		check(room.dummy.contacts.size() - before == rhythm.strike_count(), "%s: the dummy takes %d contacts (got %d: %s)" % [id, rhythm.strike_count(), room.dummy.contacts.size() - before, str(room.dummy.contacts.slice(before).map(func(c) -> String: return str(c.get("id", c)) if c is Dictionary else str(c)))])
		check(crescents().is_empty(), "%s: smears finish after the combo ends" % id)

	# Red finale: red warning starts RED_LEAD before the red beat; the blue cue counts down.
	play_rhythm(4)
	var red: DeerClashRhythm = deer.clash_phase.rhythm
	var red_t: float = red.strikes[-1].t
	check(deer.warning_kind == &"red" and deer.clash_phase.is_red_move(), "Red finale raises the red warning")
	while deer.clash_phase.step_time + 0.000001 < red_t - DeerClashPhase.RED_LEAD: tick(1)
	check(absf(deer.clash_phase.red_warning_age()) <= 1.0 / 60.0 + 0.0001, "Red warning age zero remains 5/12 s before the red beat")
	var next := deer.clash_phase.next_parry_contact_in()
	check(absf(next - (red_t - deer.clash_phase.step_time)) < 0.001, "Parry cue counts down to the red beat")
	check(deer.warning_is_beat() and not deer.vfx.red_warning.visible, "Later red strike is a short beat and is hidden before its start")
	while deer.clash_phase.red_warning_age() < DangerFlash.PEAK_TIME: tick(1)
	check(deer.vfx.red_warning.visible and deer.vfx.red_warning.beat and not deer.vfx.red_warning.pieces[1].visible, "Later red strike displays its short chest beat without gathering shards")
	tick(240)

	# Slow motion keeps the beats.
	play_rhythm(1)
	var first: float = deer.clash_phase.rhythm.strikes[0].t
	Engine.time_scale = 0.25
	var real := 0.0
	while deer.attack_hitbox.attack == null and real < 10.0:
		tick(1)
		real += 1.0 / 60.0
	Engine.time_scale = 1.0
	check(absf(deer.clash_phase.step_time - first) <= 0.25 / 60.0 + 0.0001, "Quarter speed opens the first strike on its beat")
	tick(240)

	# AI: far → closer first; rhythms vary; a parry run sometimes adds a gold charge.
	var phase := deer.clash_phase
	var saw_far := true
	var repeats := 0
	var charges := 0
	phase.rhythm_history.clear()
	for i in 300:
		phase.parry_streak = 3 if i % 2 == 0 else 0
		var composed := phase._compose()
		var rhythm_step: Dictionary = composed.filter(func(s: Dictionary) -> bool: return s.move == &"rhythm")[0]
		charges += composed.filter(func(s: Dictionary) -> bool: return s.move == &"charge").size()
		var history := phase.rhythm_history
		if history.size() >= 3 and history[-1] == history[-2] and history[-2] == history[-3]: repeats += 1
	check(repeats == 0, "AI never plays one rhythm three times running")
	check(charges > 40 and charges < 140, "A parry run is answered with a gold charge about 60%% of the time (%d / 150)" % charges)
	room.adapter.set_preview_target(Vector2(deer.position.x - 600, 555))
	phase.aim_x = deer.position.x - 600
	var far := phase._compose()
	saw_far = far[0].move in [&"dash", &"pull"] and far[1].move == &"rhythm"
	check(saw_far, "A far target is closed with a dash or pull before the rhythm")
	room.adapter.set_preview_target(Vector2(688, 555))

	if capture_frames:
		for r in DeerClashRhythm.ORDER.size():
			DirAccess.make_dir_recursive_absolute(output.path_join("r%d" % (r + 1)))
			room.reset_room(); await process_frame; await process_frame
			deer = room.adapter.deer
			deer.set_physics_process(false); deer.vfx.set_process(false)
			room.set_physics_process(false); room.player.set_physics_process(false)
			play_rhythm(r + 1)
			var f := 0
			while f < 200 and (deer.state == DeerBoss.State.CLASH or not crescents().is_empty() or f < 10):
				tick(1)
				await snapshot("r%d/frame_%03d" % [r + 1, f])
				f += 1
	current_scene = null
	room.free()
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "Rhythms leave progress untouched")
	print("WIND RHYTHM: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
