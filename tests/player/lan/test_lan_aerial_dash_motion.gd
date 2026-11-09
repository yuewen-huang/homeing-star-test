extends "../../support/harness.gd"
## Real physics/input coverage for dash travel, exit momentum and thin obstacles.
var player: LanPlayer
var world: Node2D
var output: String
var traces: Dictionary = {}

func step(count := 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func release() -> void:
	for action in [&"jump", &"ui_left", &"ui_right", &"instant_dash"]:
		Input.action_release(action)

func reset() -> void:
	release()
	player.solid_blockers.clear()
	player.world_min_x = 0
	player.world_max_x = 1280
	player.reset_after_map_fall(Vector2(640, 500))
	await step(3)
	Input.action_press(&"jump")
	await step(12)
	Input.action_release(&"jump")
	await step()

func block(rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.position = rect.get_center()
	body.add_child(collision)
	var art := Polygon2D.new()
	var half := rect.size * 0.5
	art.polygon = PackedVector2Array([Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)])
	art.color = Color(0.2,0.27,0.3)
	body.add_child(art)
	world.add_child(body)
	return body

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	root.size = Vector2i(1280,720)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	player = load("res://scenes/player/lan/lan_player.tscn").instantiate()
	player.world_min_x = 0
	player.world_max_x = 1280
	player.fallback_ground_y = 500
	player.position = Vector2(640,500)
	world.add_child(player)
	var floor_art := Polygon2D.new()
	floor_art.polygon = PackedVector2Array([Vector2(0,500),Vector2(1280,500),Vector2(1280,720),Vector2(0,720)])
	floor_art.color = Color(0.12,0.16,0.19)
	world.add_child(floor_art)
	await step(3)
	for direction: float in [1.0,-1.0]:
		await reset()
		var action := &"ui_right" if direction > 0 else &"ui_left"
		Input.action_press(action)
		player.start_aerial_dash(direction)
		var origin := player.position
		var previous_x := origin.x
		var samples: Array = []
		var held_height := true
		var invulnerability_correct := true
		for i in 30:
			await step()
			var dx := (player.position.x - previous_x) * direction
			samples.append({"frame":i+1,"x":player.position.x,"dx":dx,"vx":player.velocity.x,"elapsed":player.aerial_dash_elapsed})
			held_height = held_height and absf(player.position.y-origin.y)<0.1
			if player.attack_state == player.AttackState.AERIAL_DASH:
				invulnerability_correct = invulnerability_correct and (player.is_invulnerable() == (player.aerial_dash_elapsed < 0.12))
			if direction > 0 and i in [0,7,14,17]: await capture("dash_%02d" % i)
			previous_x = player.position.x
			if player.attack_state != player.AttackState.AERIAL_DASH: break
		traces[str(direction)] = samples
		check(absf((player.position.x-origin.x)*direction-230.0)<0.1,"Mirrored dash travels 230 px through real physics")
		check(samples.size()==18,"Dash lasts 18 physics frames at 60 Hz")
		check(held_height,"Dash holds height only during its active motion")
		check(float(samples[0].dx)>10,"First frame already has a committed burst")
		check(absf(player.velocity.x-direction*player.air_movement_speed)<0.1,"Exit inherits normal airborne speed without a zero-speed frame")
		check(invulnerability_correct and not player.is_invulnerable(),"Only the first 0.12 seconds remain invulnerable")
		var exit_x := player.position.x
		await step(3)
		check((player.position.x-exit_x)*direction>8 and player.position.y>origin.y,"Held direction continues moving while gravity resumes")
		Input.action_release(action)
		Input.action_press(&"ui_left" if direction>0 else &"ui_right")
		await step(7)
		check(player.velocity.x*direction<0,"Normal steering can reverse after the dash")
		Input.action_press(&"jump")
		await step(2)
		check(player.double_jump_used and player.velocity.y<0 and player.aerial_dash_used,"Second jump responds after dash without refilling dash")
	# Check high-speed sweeps against a physical wall on both sides.
	for direction: float in [1.0,-1.0]:
		await reset()
		var origin := player.position.x
		var wall := block(Rect2(origin+direction*70-2,200,4,300))
		await step(2)
		player.start_aerial_dash(direction)
		await step(20)
		check((player.position.x-origin)*direction<70,"Four-pixel physical wall cannot be crossed")
		check(player.attack_state!=player.AttackState.AERIAL_DASH and player.aerial_dash_used,"Wall contact exits dash without refilling or hovering")
		wall.queue_free()
		await step(2)
		await reset()
		origin = player.position.x
		player.register_solid_blocker(Rect2(origin+direction*70-1,200,2,300))
		player.start_aerial_dash(direction)
		await step(20)
		check((player.position.x-origin)*direction<70,"Two-pixel authored blocker stops on the near side")
		check(player.attack_state!=player.AttackState.AERIAL_DASH,"Authored blocker ends dash promptly")
	await reset()
	player.world_max_x=player.position.x+50
	player.start_aerial_dash(1)
	await step(8)
	check(player.position.x<=player.world_max_x and player.attack_state!=player.AttackState.AERIAL_DASH,"Room edge clips travel without stretching the dash over 0.30 s")
	# Real input: jump from one physical platform, dash across the gap, then land.
	await reset()
	player.fallback_ground_y=1000
	var left := block(Rect2(0,500,260,100))
	var right := block(Rect2(470,500,810,100))
	floor_art.visible=false
	player.reset_after_map_fall(Vector2(180,500))
	await step(3)
	Input.action_press(&"ui_right")
	Input.action_press(&"jump")
	await step(12)
	Input.action_release(&"jump")
	Input.action_press(&"instant_dash")
	await step(2)
	Input.action_release(&"instant_dash")
	check(player.attack_state==player.AttackState.AERIAL_DASH,"U input starts dash during a real platform jump")
	await step(14)
	await capture("gap_dash")
	await step(30)
	await capture("gap_landing")
	check(player.position.x>470 and absf(player.position.y-500)<0.1 and not player.aerial_dash_used,"Jump/dash/held steering lands on the far platform and refreshes the budget")
	check(player.get_node("StateTrace").report_count==0,"Motion and animation ownership remain consistent")
	var file := FileAccess.open(output.path_join("aerial_dash_motion.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(traces,"\t"))
	release()
	expect_save_untouched()
	world.queue_free()
	await step(3)
	finish("AERIAL DASH MOTION")
