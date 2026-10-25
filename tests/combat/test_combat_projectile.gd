extends "../support/harness.gd"
## CombatProjectile2D (restructure P4, 2026-10-19), the shared flight of LanSwordWaveProjectile,
## MasterSwordQi and MasterGroundWave: flight on its owner's action time, life / travel / map
## limits, the sprite sheet on that clock, one hit per target, and each subclass still built
## on it.

class Clock extends RefCounted:
	var value := 1.0
	func get_action_time_scale() -> float: return value

func run() -> void:
	use_memory_progress()
	var world := Node2D.new()
	root.add_child(world)

	var shot := CombatProjectile2D.new()
	world.add_child(shot)
	var clock := Clock.new()
	shot.clock_source = clock
	shot.start(Vector2(100, 50), Vector2(200, 0))
	shot.life = 1.0
	var spent := [false]
	shot.spent.connect(func() -> void: spent[0] = true)
	shot._process(0.25)
	check(shot.position.is_equal_approx(Vector2(150, 50)) and is_equal_approx(shot.age, 0.25), "It flies on its owner's clock at full speed")
	clock.value = 0.1
	shot._process(0.5)
	check(shot.position.is_equal_approx(Vector2(160, 50)) and is_equal_approx(shot.age, 0.3), "Bullet time slows the flight and the age together")
	clock.value = 0.0
	shot._process(1.0)
	check(shot.position.is_equal_approx(Vector2(160, 50)), "A paused owner stops it")
	shot.advance(0.7)
	check(spent[0] and shot.is_queued_for_deletion(), "It is spent and frees itself when its life runs out")

	var runner := CombatProjectile2D.new()
	world.add_child(runner)
	runner.start(Vector2.ZERO, Vector2(-100, 0))
	runner.max_distance = 150.0
	runner.advance(1.0)
	check(not runner.is_queued_for_deletion(), "It keeps going before its travel limit")
	runner.advance(0.6)
	check(runner.is_queued_for_deletion(), "It is spent after its travel limit, in either direction")

	var edge := CombatProjectile2D.new()
	world.add_child(edge)
	edge.start(Vector2(90, 0), Vector2(100, 0))
	edge.world_min_x = 0.0
	edge.world_max_x = 100.0
	edge.advance(0.05)
	check(not edge.is_queued_for_deletion(), "It stays inside the map")
	edge.advance(0.1)
	check(edge.is_queued_for_deletion(), "It is freed once past the map edge")

	var art := CombatProjectile2D.new()
	world.add_child(art)
	art.self_stepping = false
	var sheet := art.add_sheet(LanSwordWaveProjectile.TEXTURE, 4, 10.0, 1.2, Vector2(0, -32), true)
	check(sheet.hframes == 4 and sheet.flip_h and sheet.scale.is_equal_approx(Vector2(1.2, 1.2)) and sheet.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "add_sheet builds a mirrored pixel sheet")
	var frames: Array[int] = []
	for i in 6:
		art.advance(0.1)
		frames.append(sheet.frame)
	check(frames == [1, 2, 3, 0, 1, 2], "The sheet loops on the projectile's age (%s)" % str(frames))
	art.position = Vector2.ZERO
	art._process(1.0)
	check(art.position == Vector2.ZERO and is_equal_approx(art.age, 0.6), "With self_stepping off only its owner moves it")
	var target := Node.new()
	check(art.first_hit(target) and not art.first_hit(target), "first_hit is true once per target")
	target.free()

	var lan_wave := LanSwordWaveProjectile.new()
	var wave := (load("res://scenes/bosses/master/master_ground_wave.tscn") as PackedScene).instantiate()
	check(lan_wave is CombatProjectile2D, "Lan's wave remains a combat projectile")
	check(wave is MasterGroundWave and wave is CombatProjectile2D and wave.z_index == 1, "The master's ground wave scene is a combat projectile")
	for node: Node in [lan_wave, wave]:
		node.free()
	for node in world.get_children():
		node.free()
	world.free()
	expect_save_untouched()
	finish("COMBAT PROJECTILE")
