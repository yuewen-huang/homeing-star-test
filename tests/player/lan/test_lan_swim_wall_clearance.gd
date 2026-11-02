extends "test_lan_water_boundaries.gd"
## Test the opaque head/torso core against real walls. Thin hair/cloth can exceed
## the stable gameplay capsule; its size must not track those animation pixels.
var _pixels: Dictionary={}
var _rocks: Array[Rect2]=[Rect2(300,500,100,800),Rect2(2200,500,100,800)]

func run() -> void:
	use_memory_progress()
	build()
	for rock in _rocks: add_rock(rock)
	await step(3)
	for side in [-1.0,1.0]:
		await place(Vector2(750 if side<0 else 1850,820))
		await step(3)
		var action:=&"ui_left" if side<0 else &"ui_right"
		Input.action_press(action)
		var worst:=0.0
		for i in 170:
			await step(1)
			worst=maxf(worst,visible_penetration())
		check(worst<1.0,"Swimming head/torso stays outside wall %.0f (worst %.2f px)" % [side,worst])
		await screenshot("straight_"+str(int(side)))
		Input.action_press(&"ui_up")
		worst=0.0
		for i in 45:
			await step(1)
			worst=maxf(worst,visible_penetration())
		check(worst<1.0,"Turning upward against wall %.0f keeps the whole pose clear (%.2f px)" % [side,worst])
		await screenshot("turn_"+str(int(side)))
		release_all()
		Input.action_press(action)
		Input.action_press(&"instant_dash")
		worst=0.0
		for i in 38:
			await step(1)
			worst=maxf(worst,visible_penetration())
		check(worst<1.0,"Swimming kick into wall %.0f cannot bury the pose (%.2f px)" % [side,worst])
		await screenshot("kick_"+str(int(side)))
		release_all()
		Input.action_press(&"ui_right" if side<0 else &"ui_left")
		var before:=player.position
		await step(90)
		check((player.position.x-before.x)*-side>70,"The swimmer can turn and move away from wall %.0f" % side)
	var body:=player.get_node("CollisionShape2D") as CollisionShape2D
	check(body.shape.size==Vector2(24,58) and body.position==Vector2(0,-29),"Dry-land body size and feet anchor remain unchanged")
	player.set_physics_process(false)
	player.swim.play_swim_animation(player,LanSwimMotor.ANIM_GLIDE)
	player.animated_sprite.frame=0
	var first:=player.swim._clearance_query(player)
	player.animated_sprite.frame=10
	var second:=player.swim._clearance_query(player)
	check(first.shape==second.shape and first.transform.is_equal_approx(second.transform),"Animation frames cannot resize or shift the swim collision capsule")
	release_all()
	world.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("LAN SWIM WALL CLEARANCE")

func visible_penetration() -> float:
	var sprite:=player.animated_sprite
	if sprite.animation not in LanSwimMotor.PINNED_ANIMATIONS: return 0.0
	var key:="%s:%d" % [sprite.animation,sprite.frame]
	if not _pixels.has(key):
		var image:=sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame).get_image()
		var points:=PackedVector2Array()
		var used:=image.get_used_rect()
		for y in range(used.position.y,used.end.y,2):
			for x in range(used.position.x,used.end.x,2):
				var core:=x>=3 and y>=3 and x<image.get_width()-3 and y<image.get_height()-3
				if not core: continue
				for dy in range(-3,4):
					for dx in range(-3,4):
						if image.get_pixel(x+dx,y+dy).a<0.5: core=false
				if core: points.append(Vector2(x+0.5,y+0.5)-image.get_size()*0.5)
		_pixels[key]=points
	var worst:=0.0
	for pixel in _pixels[key]:
		var local: Vector2=pixel
		if sprite.flip_h: local.x=-local.x
		var point:=world.to_local(sprite.to_global(sprite.offset+local))
		for rock in _rocks:
			if rock.has_point(point): worst=maxf(worst,minf(point.x-rock.position.x,rock.end.x-point.x))
	return worst

func screenshot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var output:=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	var camera:=world.get_node_or_null("ReviewCamera") as Camera2D
	if camera==null:
		camera=Camera2D.new()
		camera.name="ReviewCamera"
		world.add_child(camera)
		camera.make_current()
	camera.position=player.position-Vector2(0,100)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
