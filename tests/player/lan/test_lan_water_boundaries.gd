extends "test_lan_swimming.gd"
## Reproduce authored curved transitions against real solid bodies, both mirrors.


func run() -> void:
	use_memory_progress()
	build()
	add_rock(Rect2(300,500,100,800))
	add_rock(Rect2(2200,500,100,800))
	await step(3)
	for side in [-1.0,1.0]:
		var x:=414.0 if side<0 else 2186.0
		await place(Vector2(x,530))
		player.facing_direction=side
		var entered:=false
		var safe:=true
		var visible_safe:=true
		for i in 125:
			await step(1)
			entered=entered or player.swim.is_splashing()
			safe=safe and clear_of_rocks()
			visible_safe=visible_safe and torso_clear()
		check(entered,"Entry transition exercised facing %.0f at pool wall" % side)
		check(safe,"Curved entry never sweeps the body into a wall, facing %.0f" % side)
		check(visible_safe,"Entry torso stays on the water side of the wall, facing %.0f" % side)
		await place(Vector2(x,900))
		player.facing_direction=-side
		await step(3)
		Input.action_press(&"ui_up")
		var surfaced:=false
		safe=true
		visible_safe=true
		for i in 210:
			await step(1)
			surfaced=surfaced or player.swim.is_surfacing()
			safe=safe and clear_of_rocks()
			visible_safe=visible_safe and torso_clear()
		check(surfaced,"Surfacing transition exercised beside wall %.0f" % side)
		check(safe,"Curved surfacing never sweeps the body into wall %.0f" % side)
		check(visible_safe,"Surfacing torso stays outside wall %.0f" % side)
		release_all()
	# The volume can extend above a submerged roof; that top is not reachable air.
	var roof:=add_rock(Rect2(900,530,300,20))
	await place(Vector2(1050,700))
	await step(3)
	Input.action_press(&"ui_up")
	var false_surface:=false
	var roof_safe:=true
	for i in 180:
		await step(1)
		false_surface=false_surface or player.swim.is_surfacing() or player.swim.is_floating()
		roof_safe=roof_safe and clear_of_rocks()
	check(not false_surface,"A submerged solid roof prevents a false surfacing/float")
	check(roof_safe and player.position.y>=608-0.2,"Rising stops below the real roof")
	check(torso_clear(),"The rotated swim torso also stays below the ceiling")
	release_all()
	roof.queue_free()
	await step(3)
	# An explicitly internal seam does not become a second breathing surface.
	var internal:=UnderwaterVolume.new()
	internal.position=Vector2(2400,500)
	internal.size=Vector2(400,700)
	internal.show_surface=false
	world.add_child(internal)
	internal.register_to(player)
	await place(Vector2(2600,530))
	await step(3)
	check(not player.swim.is_splashing(),"An internal water seam never starts a free-surface splash")
	await place(Vector2(2600,900))
	await step(3)
	Input.action_press(&"ui_up")
	var internal_surface:=false
	for i in 180:
		await step(1)
		internal_surface=internal_surface or player.swim.is_surfacing() or player.swim.is_floating()
	check(not internal_surface,"An internal water seam never starts surfacing or refills by floating")
	release_all()
	internal.queue_free()
	await step(3)
	# A volume can disappear mid-animation: no stale pinned transition may own it.
	await place(Vector2(1500,530))
	await step(3)
	check(player.swim.is_splashing(),"Volume-removal case starts during the entry splash")
	volume.unregister_from(player)
	await step(2)
	check(not swimming() and not player.swim.is_splashing(),"Removing water cancels a running transition immediately")
	world.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("LAN WATER BOUNDARIES")


func add_rock(area: Rect2) -> StaticBody2D:
	var body:=StaticBody2D.new()
	body.position=area.get_center()
	var shape:=CollisionShape2D.new()
	var box:=RectangleShape2D.new()
	box.size=area.size
	shape.shape=box
	body.add_child(shape)
	world.add_child(body)
	return body


func clear_of_rocks() -> bool:
	var query:=PhysicsShapeQueryParameters2D.new()
	var box:=RectangleShape2D.new()
	box.size=Vector2(23.6,57.6)
	query.shape=box
	query.transform=Transform2D(0,player.global_position+LanSwimMotor.BODY_PROBE)
	query.collision_mask=1
	query.exclude=[player.get_rid()]
	return player.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()


func torso_clear() -> bool:
	var point:=LanSwimMotor.body_point(player)
	if is_nan(point.x): return true
	var query:=PhysicsPointQueryParameters2D.new()
	query.position=player.global_position+point
	query.collision_mask=1
	query.exclude=[player.get_rid()]
	return player.get_world_2d().direct_space_state.intersect_point(query,1).is_empty()
