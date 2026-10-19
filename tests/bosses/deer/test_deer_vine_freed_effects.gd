extends SceneTree
## Exercise effect expiry across real frame boundaries, including typed arrays
## containing consecutive freed references, nulls and surviving effects.

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func add_freed_entries(effects: Array, script: Script) -> void:
	var first: Node = script.new()
	var second: Node = script.new()
	effects.append(first)
	effects.append(second)
	effects.append(null)
	first.free()
	second.free()

func run() -> void:
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	var vine: DeerVinePhase = deer.vine_phase
	var treant := DeerVineTreant.new()
	room.add_child(treant)
	treant.setup(vine, Vector2(deer.world_min_x + 100.0, vine.ground_y))
	treant._next_cast = INF
	vine.treants.append(treant)

	# RootSpikeVolley actually expires and queue_free() runs at a frame boundary.
	for cycle in 3:
		var volley := treant.cast_spikes()
		volley.set_process(false)
		for frame in 600:
			volley._process(1.0 / 60.0)
			if volley.is_queued_for_deletion(): break
		check(volley.is_queued_for_deletion(), "spike volley %d finishes naturally" % cycle)
		await process_frame
		await process_frame
		check(not is_instance_valid(volley), "spike volley %d is freed" % cycle)
		treant.step(0.0, true)
		check(treant.volleys.is_empty(), "expired volley %d leaves the treant array" % cycle)

	var surviving_volley := treant.cast_spikes()
	surviving_volley.set_process(false)
	add_freed_entries(treant.volleys, RootSpikeVolley)
	treant.step(0.0, true)
	check(treant.volleys.size() == 1 and treant.volleys[0] == surviving_volley, "treant removes adjacent stale entries and keeps live spikes")
	for frame in 600: treant.step(1.0 / 60.0, true)
	check(treant.volleys.size() == 1, "continued treant updates keep the surviving volley")

	var stampede := DeerStagStampede.new()
	room.add_child(stampede)
	stampede.setup(vine, 1.0)
	stampede.add_wave(1.0, 1, false, 1000.0)
	stampede._spawn({"from_x": deer.world_min_x - 260.0, "direction": 1.0, "king": false})
	var phantom := stampede.phantoms[0]
	add_freed_entries(stampede.phantoms, DeerStagStampede.DeerStagPhantom)
	stampede.step(0.0)
	check(stampede.phantoms.size() == 1 and stampede.phantoms[0] == phantom, "stampede prunes freed spirits and keeps the live spirit")
	vine.stampedes.append(stampede)
	var wind := DeerVineWind.new()
	room.add_child(wind)
	wind.setup(vine, &"push", 1000.0)
	vine._old_winds.append(wind)
	add_freed_entries(vine.stampedes, DeerStagStampede)
	add_freed_entries(vine.treants, DeerVineTreant)
	add_freed_entries(vine._old_winds, DeerVineWind)
	vine._step_world(0.0)
	check(vine.stampedes.size() == 1 and vine.stampedes[0] == stampede, "world prunes freed stampedes and keeps the live wave")
	check(vine.treants.size() == 1 and vine.treants[0] == treant, "world prunes freed treants and keeps the live summon")
	check(vine._old_winds.size() == 1 and vine._old_winds[0] == wind, "world prunes freed winds and keeps the live field")

	add_freed_entries(vine.strikes, DeerVineStrike)
	vine._step_strikes(0.0)
	check(vine.strikes.is_empty(), "strike updates remove freed references")
	var snapped := DeerVineStrike.new()
	room.add_child(snapped)
	snapped.snapped = true
	vine.strikes.append(snapped)
	var cancelled := DeerVineStrike.new()
	room.add_child(cancelled)
	vine.strikes.append(cancelled)
	add_freed_entries(vine.strikes, DeerVineStrike)
	vine._clear_strikes(true)
	check(vine.strikes.size() == 1 and vine.strikes[0] == snapped, "strike cancellation prunes freed entries and preserves snapped vines")
	check(cancelled.finished and cancelled.is_queued_for_deletion(), "live unsnapped strike is cancelled and freed")
	snapped.finished = true
	vine._step_strikes(0.0)
	check(vine.strikes.is_empty() and snapped.is_queued_for_deletion(), "finished snapped vine is removed after recovery")
	vine.cancel()
	await process_frame
	await process_frame
	check(vine.treants.is_empty() and vine.stampedes.is_empty() and vine._old_winds.is_empty(), "phase cancellation still clears all tracked effects")
	print("FREED EFFECTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
