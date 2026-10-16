extends SceneTree

## Pixel slash demo (PixelSlash + DeerPixelSlashDemo) in the development room's
## 「鹿 · 像素斩击 DEMO」 entry. Optional user arg: directory for render snapshots.

var room
var demo: DeerPixelSlashDemo
var checks := 0
var failures := 0
var output := ""
## Second user arg "frames": also save every frame of each continuous combo for GIFs.
var capture_frames := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale/60.0
		room.adapter.deer._physics_process(delta)
		room._physics_process(delta)
		room.adapter.deer.vfx._process(delta)
		demo.update()

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func wait_for_slash(limit: int) -> PixelSlash:
	var before := demo.spawned
	for i in limit:
		tick(1)
		if demo.spawned > before: return demo.get_child(demo.get_child_count() - 1) as PixelSlash
	return null

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	capture_frames = args.size() > 1 and args[1] == "frames"
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	var index: int = room.BOSS_CATALOG.map(func(e: Dictionary) -> String: return e.name).find("鹿 · 像素斩击 DEMO")
	check(index >= 0, "Development room lists the pixel slash demo")
	room.select_boss(index); await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false); deer.vfx.set_process(false)
	demo = room.adapter.slash_demo
	check(deer.phase == 3 and demo != null and demo.get_parent() == deer, "Demo opens in the wind phase with the slash director inside the deer specimen")

	# Wind strikes grow production crescents (DeerClashPhase); the demo adds no second slash.
	for entry: Array in [[0, "thrust"], [1, "rear_gore"], [3, "flick"]]:
		var before := demo.spawned
		room.play_action(entry[0])
		var crescent_seen := false
		for i in 240:
			tick(1)
			crescent_seen = crescent_seen or deer.clash_phase.smears.any(func(s) -> bool: return is_instance_valid(s) and s.shape == &"crescent")
			if deer.attack_hitbox.attack != null and crescent_seen: break
		check(crescent_seen and demo.spawned == before, "Real %s shows the production crescent and no duplicate demo slash" % entry[1])
		tick(120)
	await snapshot("wind_crescent")

	# Same slash at quarter speed: half as far through after the same real frames.
	var probe := PixelSlash.new().configure({"duration": 0.12, "tail": 0.16})
	root.add_child(probe)
	probe.advance(0.03)
	var quarter := probe.tip_param()
	check(quarter > 0.0 and quarter < probe.end_angle, "Tip moves part-way along the arc")
	probe.advance(1.0)
	check(probe.is_done(), "Tip and tail are gone once swing and tail time have passed")
	probe.free()

	# Effect gallery: key 5 plays the library selection in front of the deer.
	var labels := DeerPixelSlashDemo.gallery_labels()
	check(room.library_picker.visible and room.library_picker.item_count == labels.size() and labels[-1] == "全部轮播", "Library dropdown lists the effect gallery")
	for i in DeerPixelSlashDemo.GALLERY.size():
		var entry: Dictionary = DeerPixelSlashDemo.GALLERY[i]
		room.select_combo_library(i)
		check(room.ultimate_button.text.begins_with("特效 · " + entry.label), "Key 5 is labelled with %s" % entry.label)
		var before := demo.spawned
		room.play_action(4)
		var expected: int = _part_count(entry)
		check(demo.spawned - before == expected, "%s spawns its %d parts" % [entry.label, expected])
		var shot_at := 0.0
		if entry.has("sequence"):
			shot_at = float(PixelSlash.build_path(entry.sequence.path).total) * 0.45
		elif entry.has("flow"):
			shot_at = float(PixelSlash.build_path(entry.flow.path).total) * 0.62
		else:
			for part: Dictionary in entry.parts: shot_at = maxf(shot_at, float(part.get("delay", 0.0)))
			shot_at += float(entry.parts[-1].duration) * 0.6
		var frames := ceili(shot_at * 60.0)
		tick(frames)
		await snapshot("gallery_%02d" % i)
		tick(ceili(DeerPixelSlashDemo.gallery_length(entry) * 60.0) - frames + 2)
		await process_frame
		check(demo.get_child_count() == 0, "%s is completely gone after its length" % entry.label)
	var delayed := PixelSlash.new().configure({"delay": 0.1, "duration": 0.1, "tail": 0.1})
	root.add_child(delayed)
	delayed.advance(0.05)
	check(delayed.age < 0.0 and delayed._samples.size() == 1, "A delayed part stays hidden until its delay has passed")
	delayed.free()
	# Continuous paths: speed is continuous at every joint and the blade only lifts on jump.
	var flow: Array = DeerPixelSlashDemo.GALLERY.filter(func(e: Dictionary) -> bool: return e.has("flow"))
	check(flow.size() == 6, "Gallery has six continuous combos")
	var routes: Array = flow.map(func(e: Dictionary) -> Array: return e.flow.path)
	var seven: Array = DeerPixelSlashDemo.GALLERY.filter(func(e: Dictionary) -> bool: return e.has("sequence"))
	check(seven.size() == 1 and seven[0].label == "连斩 · 七式", "Gallery has the seven-form sequence")
	routes.append(seven[0].sequence.path)
	# Speed across every joint between two drawing commands (hard braking inside a command,
	# like a follow-through stop, is intended and continuous).
	var worst_jump := 0.0
	var joint_count := 0
	for route: Array in routes:
		var built := PixelSlash.build_path(route)
		var points: PackedVector2Array = built.points
		var times: PackedFloat32Array = built.times
		var strokes: PackedInt32Array = built.strokes
		var rate := func(i: int) -> float: return points[i + 1].distance_to(points[i]) / maxf(times[i + 1] - times[i], 0.00001)
		for j: int in built.joints:
			if j < 2 or j + 2 >= points.size() or strokes[j + 2] != strokes[j] or strokes[j - 2] != strokes[j]: continue
			# Interval speeds are mid-interval values; extrapolate each side half an interval
			# to the joint so steady acceleration (a hard brake or wind-up) is not a "jump".
			var before: float = rate.call(j - 1) + (rate.call(j - 1) - rate.call(j - 2)) * 0.5
			var after: float = rate.call(j) - (rate.call(j + 1) - rate.call(j)) * 0.5
			worst_jump = maxf(worst_jump, absf(after - before) / maxf(before, 1.0))
			joint_count += 1
	check(joint_count > 40 and worst_jump < 0.1, "Tip speed is continuous across all %d command joints (worst %.3f)" % [joint_count, worst_jump])
	var thrusts := PixelSlash.build_path(flow[3].flow.path)
	check((thrusts.strokes as PackedInt32Array)[-1] == 3, "Jumps split 回马连刺 into four blade strokes")
	var stepped := PixelSlash.new().configure({"shape": &"path", "path": flow[0].flow.path, "tail": 0.16})
	root.add_child(stepped)
	stepped.advance(0.2)
	var coarse := stepped._samples.size()
	stepped.free()
	var fine := PixelSlash.new().configure({"shape": &"path", "path": flow[0].flow.path, "tail": 0.16})
	root.add_child(fine)
	for i in 20: fine.advance(0.01)
	check(fine._samples.size() == coarse, "Path trail is the same whatever the frame step (%d vs %d samples)" % [fine._samples.size(), coarse])
	fine.free()
	# Seven-form sequence: contacts, hit-stop, finisher on the ground, repeatable sparks.
	var seven_built := PixelSlash.build_path(seven[0].sequence.path, seven[0].sequence.squash)
	var contacts: Array = seven_built.contacts
	check(contacts.size() == 7 and contacts.filter(func(c: Dictionary) -> bool: return c.finisher).size() == 1, "七式 has seven contacts, one finisher")
	var landing := DeerPixelSlashDemo.SEQUENCE_ANCHOR.y + (contacts[-1].at as Vector2).y
	check(absf(landing) < 12.0, "Finisher lands on the deer's ground line (%.0f px off)" % landing)
	var highest := 0.0
	for p: Vector2 in seven_built.points: highest = minf(highest, p.y)
	check(DeerPixelSlashDemo.SEQUENCE_ANCHOR.y + highest > -400.0, "Highest point stays below the development toolbar (%.0f above ground)" % -(DeerPixelSlashDemo.SEQUENCE_ANCHOR.y + highest))
	var kinds: PackedByteArray = seven_built.kinds
	check(kinds.has(PixelSlash.Kind.CARRY) and kinds.has(PixelSlash.Kind.CHARGE) and kinds.has(PixelSlash.Kind.HIT), "Route mixes strikes, blade carry and the wind-up")
	var spray_a := PixelSlash.new().configure({"shape": &"sparks", "spark_seed": 7}).make_particles()
	var spray_b := PixelSlash.new().configure({"shape": &"sparks", "spark_seed": 7}).make_particles()
	check(spray_a == spray_b and spray_a.size() == 10, "Sparks with one seed are identical")
	room.select_combo_library(DeerPixelSlashDemo.GALLERY.find(seven[0]))
	room.play_action(4)
	var combo = demo.get_child(demo.get_child_count() - 1)
	var blade: PixelSlash = combo.get_child(0)
	var first: Dictionary = contacts[0]
	while blade.age < first.time: tick(1)
	var held_age := blade.age
	tick(1)
	check(is_equal_approx(blade.age, held_age) and blade.age <= first.time + 0.0001, "Hit-stop holds the whole blade at the first contact")
	tick(4)
	check(blade.age > held_age, "The blade moves on after the hit-stop")
	tick(ceili(DeerPixelSlashDemo.gallery_length(seven[0]) * 60.0))
	await process_frame
	check(demo.get_child_count() == 0, "七式 and all its sparks, rings and embers are gone after its length")
	if capture_frames:
		for i in DeerPixelSlashDemo.GALLERY.size():
			var entry: Dictionary = DeerPixelSlashDemo.GALLERY[i]
			if not entry.has("flow") and not entry.has("sequence"): continue
			room.select_combo_library(i)
			room.play_action(4)
			for f in ceili(DeerPixelSlashDemo.gallery_length(entry) * 60.0) + 2:
				tick(1)
				await snapshot("flow_%02d_%03d" % [i, f])
	room.select_combo_library(labels.size() - 1)
	room.play_action(4)
	var total := 0
	for entry: Dictionary in DeerPixelSlashDemo.GALLERY: total += _part_count(entry)
	check(demo.get_child_count() == total, "全部轮播 queues every gallery effect")

	room.play_action(1)
	wait_for_slash(240)
	room.reset_room(); await process_frame; await process_frame
	check(not is_instance_valid(demo) or demo.get_child_count() == 0, "Reset clears pending slashes with the specimen")
	current_scene = null; room.free()
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "Demo leaves progress untouched")
	print("PIXEL SLASH: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _part_count(entry: Dictionary) -> int:
	if entry.has("parts"): return entry.parts.size()
	if entry.has("flow"): return 2 + PixelSlash.build_path(entry.flow.path).bursts.size()
	return 1  # a sequence is one container
