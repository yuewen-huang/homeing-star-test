extends "../../../support/harness.gd"
## Reproduce the sprint-to-shutter-roof bypass with the real player and the tide off.

const MAP := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const PROFILES := [
	[0, -1, -1], [0, 28, 32], [0, 29, 57], [0, 21, 45],
	[-1, 36, 46], [-1, 62, 81], [-1, 88, 106],
]

var level: SunkenCavern


func run() -> void:
	use_memory_progress()
	level = MAP.instantiate()
	root.add_child(level)
	current_scene = level
	level.tide.set_physics_process(false)
	level.stone_lion.set_physics_process(false)
	for id: String in ["c20", "c37", "c12", "c33", "c41"]:
		var east: bool = id in ["c12", "c33", "c41"]
		var start := level.marker(id)
		var side_edge := 6400.0 if east else 5120.0
		start.x = side_edge + (4.0 if east else -4.0)
		var crossings := []
		for running: bool in [false, true]:
			for profile in PROFILES:
				var got := await trial(start, east, profile, running)
				if got != Vector2.INF: crossings.append([running, profile, got])
		check(crossings.is_empty(), "calm %s: %s" % [id, crossings])
	for east: bool in [false, true]:
		var start := Vector2(6668 if east else 6084, 3582)
		var crossings := []
		for profile in PROFILES:
			var got := await trial(start, east, profile, false, true)
			if got != Vector2.INF: crossings.append([profile, got])
		check(crossings.is_empty(), "intact A17 wall from %s: %s" % ["east" if east else "west", crossings])
	level.queue_free()
	await process_frame
	expect_save_untouched()
	finish("A11 DRY BANK PROBES")


func trial(start: Vector2, east: bool, profile: Array, running: bool, lower := false) -> Vector2:
	var p := level.player
	var move := &"ui_left" if east else &"ui_right"
	var direction := -1.0 if east else 1.0
	p.reset_after_map_fall(start - Vector2(direction * 100.0, 0.0) if running else start)
	p.instant_dash_cooldown_remaining = 0
	p.combat_stats.restore_stamina(p.combat_stats.max_stamina)
	for i in 6: await physics_frame
	if running:
		Input.action_press(move)
		for i in 2: await physics_frame
		Input.action_release(move)
		for i in 2: await physics_frame
		Input.action_press(move)
		for i in 50:
			if (start.x - p.position.x) * direction < 6.0: break
			await physics_frame
	Input.action_press(move)
	var crossing := Vector2.INF
	for frame in 258:
		var wall_jump := frame > 44 and frame % 2 == 0 and p.air_state == LanPlayer.AirState.WALL_SLIDING
		if frame == profile[0] or frame == profile[1] or wall_jump: Input.action_press(&"jump")
		else: Input.action_release(&"jump")
		if frame == profile[2] or (profile[0] == -1 and frame == 0): Input.action_press(&"instant_dash")
		else: Input.action_release(&"instant_dash")
		await physics_frame
		if lower and p.position.y >= 3100.0 and p.position.y <= 3590.0:
			if (p.position.x < 6084.0 if east else p.position.x > 6670.0):
				crossing = p.position
				break
		elif not lower and p.air_state == LanPlayer.AirState.GROUNDED and p.position.y < 3200.0:
			if (p.position.x < 5116.0 if east else p.position.x > 6404.0):
				crossing = p.position
				break
	for action in [move, &"jump", &"instant_dash"]: Input.action_release(action)
	return crossing
