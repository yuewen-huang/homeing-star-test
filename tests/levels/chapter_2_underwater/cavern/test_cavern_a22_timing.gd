extends "test_sunken_cavern_graybox.gd"
## The only position reset is at the normal A22 preview entrance, before each run.
## Timed strikes and steering go through Lan's production input and physics.

var charged_launches: Array[bool] = []
var contacts: Array[int] = []


func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	observe_shaft()
	for trial in ["timed", "early", "late", "timed_left", "timed_right", "miss_without_pogo"]:
		if OS.get_cmdline_user_args().size() > 0 and not trial in OS.get_cmdline_user_args():
			continue
		await play_return(trial)
	await end_test()


func observe_shaft() -> void:
	var shaft: Node2D = level.west_shaft
	shaft.pad.fired.connect(func(charged: bool) -> void: charged_launches.append(charged))
	for i in shaft.blades.size():
		shaft.blades[i].tip.rebounded.connect(func() -> void: contacts.append(i))


func play_return(trial: String) -> void:
	var shaft: Node2D = level.west_shaft
	charged_launches.clear()
	contacts.clear()
	player.combat_stats.restore_health()
	player.reset_after_map_fall(level.marker("dry_base"))
	var charged := trial.begins_with("timed")
	var phase_target: float = shaft.OPEN_AT + 0.24
	if trial == "early":
		phase_target = shaft.OPEN_AT - 0.17
	elif not charged:
		phase_target = shaft.OPEN_UNTIL + 0.09
	shaft.clock = phase_target - 1.1
	level.snap_camera()
	print("RUN ", trial, " start frame ", frames)
	await step(3)
	check(await step_onto_west_spring(), "%s walks onto the pad" % trial)
	var takeoff_x := 2496.0
	if trial == "timed_left": takeoff_x -= 29.0
	if trial == "timed_right": takeoff_x += 29.0
	var health := player.combat_stats.health
	var pressed := false
	for i in ceili(shaft.CYCLE * 10.0 * 60.0):
		var phase: float = shaft.clock
		var phase_matches: bool = phase >= shaft.OPEN_AT + 0.10 and phase <= shaft.OPEN_UNTIL - 0.10
		if trial == "early":
			phase_matches = phase >= shaft.OPEN_AT - 0.24 and phase <= shaft.OPEN_AT - 0.10
		elif not charged:
			phase_matches = phase >= shaft.OPEN_UNTIL + 0.08 and phase <= shaft.OPEN_UNTIL + 0.18
		var gap: float = shaft.pad.position.y - player.position.y
		if phase_matches and player.velocity.y > 0.0 and gap >= 14.0 and gap <= 34.0 \
				and absf(player.position.x - takeoff_x) <= 5.0:
			release()
			print("SPRING ", trial, " frame=", frames, " phase=", phase, " at=", player.position)
			await slash_down()
			pressed = true
			break
		steer(takeoff_x)
		await step(1)
	check(pressed and charged_launches == [charged], "%s strike produces the correct spring launch" % trial)
	if not pressed or charged_launches.is_empty():
		return
	if trial == "miss_without_pogo":
		await step(205)
		check(player.position.y > 4000.0 and contacts.is_empty(),
			"A mistimed launch alone cannot reach the street")
		return
	if not charged:
		for i in shaft.blades.size():
			var landed := await strike_next(shaft.blades[i], i)
			check(landed, "%s reaches spear %d with a directional slash" % [trial, i + 1])
			if not landed: break
	# Aim the last rebound over the original one-way street platform.
	for i in 165:
		if not charged: steer(2496.0)
		if standing() and absf(player.position.y - level.marker("dry_turn").y) < 4.0:
			break
		await step(1)
	release()
	var arrived := standing() and absf(player.position.y - level.marker("dry_turn").y) < 4.0
	check(arrived and contacts == ([] if charged else [0, 1, 2])
		and charged_launches == [charged] and player.combat_stats.health == health,
		"%s lands on the street unharmed with one spring launch and %d spear strikes (pos=%s, contacts=%s, hp=%d)" %
		[trial, 0 if charged else 3, player.position, contacts, player.combat_stats.health])
	print("RUN ", trial, " end frame ", frames)
	await step(28)


func steer(target_x: float) -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	var dx := target_x - player.position.x
	if absf(dx) > 5.0:
		Input.action_press(&"ui_right" if dx > 0.0 else &"ui_left")


func strike_next(blade: Variant, index: int) -> bool:
	var peak := player.position.y
	var closest := INF
	var attempted := false
	for i in 165:
		var gap: float = blade.y - player.position.y
		var aim: float = blade.tip_x + blade.side * 16.0
		steer(2496.0 if index == 0 and gap < 42.0 and player.velocity.y < 0.0 else aim)
		if gap > 0.0: closest = minf(closest, absf(aim - player.position.x))
		if not attempted and player.velocity.y >= 0.0 and gap >= 12.0 and gap <= 34.0 \
				and absf(aim - player.position.x) < 12.0:
			print("SPEAR ", index + 1, " frame=", frames, " at=", player.position, " aim=", aim)
			await slash_down()
			attempted = true
			if contacts.has(index):
				return true
		else:
			await step(1)
		peak = minf(peak, player.position.y)
		if player.position.y > blade.y + 125.0 and player.velocity.y > 0.0:
			break
	print("SPEAR MISS ", index + 1, " peak=", peak, " closest=", closest, " at=", player.position)
	return false
