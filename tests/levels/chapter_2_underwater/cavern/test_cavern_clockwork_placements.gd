extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")

var level: SunkenCavern
var player: LanPlayer


func run() -> void:
	use_memory_progress()
	level = SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	player = level.player
	await _step(4)

	var enemies := level.get_node("ClockworkEnemies")
	var oxen := 0
	var birds := 0
	var snakes := 0
	var positions: Array[Vector2] = []
	var clear_of_mechanisms := true
	for child in enemies.get_children():
		var enemy := child as ClockworkEnemy
		positions.append(enemy.home)
		clear_of_mechanisms = clear_of_mechanisms and _clear_of_mechanisms(enemy.home)
		if enemy is ClockworkOx:
			oxen += 1
			check(_ox_lane(enemy), "%s has continuous solid footing and headroom" % enemy.name)
		elif enemy is ClockworkBird:
			birds += 1
			var flight_box := Rect2(enemy.home - Vector2(112, 55), Vector2(224, 110))
			check(_space_is_clear(flight_box), "%s has open air around its hover point" % enemy.name)
		elif enemy is ClockworkSnake:
			snakes += 1
			check(_snake_wall(enemy), "%s mounts a solid shaft wall with a free side to pass" % enemy.name)

	check([oxen, birds, snakes] == [7, 5, 5], "The authored cavern has seventeen placements")
	check(clear_of_mechanisms, "Spawn points stay away from the water volumes and reserved mechanisms")
	check(_lanes_are_spaced(positions), "Nearby enemies are separated by distance or solid rock")
	check(player.position.distance_to(level.start) < 1.0, "The entrance remains safe at spawn")

	await _play_ox(enemies.get_node("A02Ox") as ClockworkOx)
	await _play_bird(enemies.get_node("A07Bird") as ClockworkBird)
	await _play_snake(enemies.get_node("A06Snake") as ClockworkSnake)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("CAVERN CLOCKWORK PLACEMENTS")


func _ox_lane(ox: ClockworkOx) -> bool:
	var origin := ox.home
	var left := origin.x - ox.patrol_radius
	var right := origin.x + ox.patrol_radius
	for index in 17:
		var x := lerpf(left - 42.0, right + 42.0, float(index) / 16.0)
		var floor_hit := _terrain_ray(Vector2(x, origin.y - 10), Vector2(x, origin.y + 12))
		if floor_hit.is_empty() or absf(float(floor_hit.position.y) - origin.y) > 5.0:
			return false
	return _space_is_clear(Rect2(left - 53.0, origin.y - 72.0, right - left + 106.0, 68.0))


func _snake_wall(snake: ClockworkSnake) -> bool:
	var direction := Vector2.RIGHT if snake.faces_right else Vector2.LEFT
	var mount := snake.home
	for y in [-17.0, 0.0, 17.0]:
		var point := mount + Vector2(0, y)
		var wall := _terrain_ray(point + direction * 8.0, point - direction * 18.0)
		if wall.is_empty() or absf(float(wall.position.x) - mount.x) > 2.0:
			return false
	var approach := mount + direction * 8.0
	return _terrain_ray(approach, mount + direction * (snake.bite_reach + 73.0)).is_empty()


func _terrain_ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [player.get_rid()])
	return level.get_world_2d().direct_space_state.intersect_ray(query)


func _space_is_clear(area: Rect2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = area.size
	query.shape = shape
	query.transform = Transform2D(0.0, area.get_center())
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	return level.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _clear_of_mechanisms(point: Vector2) -> bool:
	for pool: Dictionary in level.layout.water:
		for volume: Array in pool.rects:
			if SunkenCavern.rect(volume).grow(36.0).has_point(point):
				return false
	var toad := level.bronze_toad
	var arena := Rect2(toad.ARENA_LEFT, toad.ORIGIN.y - 420.0,
		toad.ORIGIN.x - toad.ARENA_LEFT + 100.0, 480.0)
	if arena.has_point(point):
		return false
	var shaft_x := float(level.layout.mechanisms.west_shaft.center_x)
	if Rect2(shaft_x - 240.0, 3500.0, 480.0, 1510.0).has_point(point):
		return false
	for value: Array in level.layout.mechanisms.echoes.values():
		if point.distance_to(SunkenCavern.vector(value)) < 220.0:
			return false
	var bell := SunkenCavern.vector(level.layout.mechanisms.bell)
	return point.distance_to(bell) >= 300.0 and point.distance_to(level.marker("boss")) >= 360.0


func _lanes_are_spaced(points: Array[Vector2]) -> bool:
	for i in points.size():
		for j in range(i + 1, points.size()):
			var difference := (points[i] - points[j]).abs()
			if difference.x < 620.0 and difference.y < 250.0:
				if _terrain_ray(points[i] - Vector2(0, 25), points[j] - Vector2(0, 25)).is_empty():
					return false
	return true


func _play_ox(ox: ClockworkOx) -> void:
	player.reset_after_map_fall(Vector2(2020.0, 2558.0))
	var health := player.combat_stats.health
	var charged := await _wait_for(ox, ClockworkEnemy.Phase.ACTIVE)
	check(charged, "A2 ox charges Lan in the real west-market street")
	if not charged:
		return
	Input.action_press(&"jump")
	await _step(14)
	Input.action_release(&"jump")
	await _wait_for(ox, ClockworkEnemy.Phase.RECOVERY)
	check(player.combat_stats.health == health, "A2 leaves room to jump the charge without damage")


func _play_bird(bird: ClockworkBird) -> void:
	player.reset_after_map_fall(Vector2(4000.0, 1470.0))
	var health := player.combat_stats.health
	var warned := await _wait_for(bird, ClockworkEnemy.Phase.WINDUP)
	check(warned, "A7 bird can acquire Lan on the upper bridge")
	if not warned:
		return
	Input.action_press(&"ui_left")
	var attacked := await _wait_for(bird, ClockworkEnemy.Phase.ACTIVE)
	await _step(38)
	Input.action_release(&"ui_left")
	check(attacked and player.position.x < 3820.0 and player.combat_stats.health == health,
		"A7 has room to walk out of the locked dive")


func _play_snake(snake: ClockworkSnake) -> void:
	player.reset_after_map_fall(Vector2(2290.0, 1791.0))
	var health := player.combat_stats.health
	var warned := await _wait_for(snake, ClockworkEnemy.Phase.WINDUP)
	check(warned, "A6 snake can bite from the lower bell-shaft wall")
	if not warned:
		return
	Input.action_press(&"ui_left")
	var attacked := await _wait_for(snake, ClockworkEnemy.Phase.ACTIVE)
	await _step(22)
	Input.action_release(&"ui_left")
	check(attacked and snake.global_position == snake.home and player.combat_stats.health == health,
		"A6 leaves a safe side of the shaft outside the anchored bite")


func _wait_for(enemy: ClockworkEnemy, phase: ClockworkEnemy.Phase) -> bool:
	for i in 140:
		if enemy.phase == phase:
			return true
		await physics_frame
	return false


func _step(count: int) -> void:
	for i in count:
		await physics_frame
