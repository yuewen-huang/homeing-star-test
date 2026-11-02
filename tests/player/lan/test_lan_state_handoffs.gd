extends "../../support/harness.gd"
## Real physics/input: a replacement animation must not strand an action lock.
const PLAYER := preload("res://scenes/player/lan/lan_player.tscn")
var player: LanPlayer
var world: Node2D

func step(count: int) -> void:
	for i in count: await physics_frame

func release() -> void:
	for action in [&"ui_left",&"ui_right",&"jump",&"ui_up",&"ui_down",&"parry"]:
		Input.action_release(action)

func reset(at: Vector2) -> void:
	release()
	player.set_input_frozen(false)
	player.ground_surfaces.clear()
	player.climbing.climbables.clear()
	player.reset_after_map_fall(at)
	await step(2)

func run() -> void:
	use_memory_progress()
	world=Node2D.new()
	root.add_child(world)
	current_scene=world
	player=PLAYER.instantiate() as LanPlayer
	player.world_min_x=-5000
	player.world_max_x=5000
	player.fallback_ground_y=1000
	player.position=Vector2(0,1000)
	world.add_child(player)
	await step(3)
	# Running into S on a finite platform; walking off takes the body animation.
	await reset(Vector2(160,500))
	player.register_ground_surface(Rect2(0,500,200,12))
	player.play_run()
	Input.action_press(&"ui_right")
	player.start_slide()
	var fell:=false
	for i in 180:
		await step(1)
		fell=fell or player.air_state==LanPlayer.AirState.FALLING
	release()
	await step(90)
	print("SLIDE EXIT state=",player.ground_action_state," air=",player.air_state," animation=",player.animated_sprite.animation," velocity=",player.velocity)
	check(fell,"Slide really leaves the finite upper platform")
	check(player.ground_action_state==LanPlayer.GroundActionState.NONE,"Falling out of a slide releases the slide action lock")
	check(absf(player.velocity.x)<0.1,"Releasing movement stops after slide/drop/landing")
	Input.action_press(&"jump")
	await step(3)
	check(player.air_state==LanPlayer.AirState.RISING,"Jump input works again after the slide/drop handoff")
	await reset(Vector2(0,1000))
	player.start_slide()
	await step(100)
	check(player.position.x>100,"A supported slide retains its authored forward movement")
	check(player.ground_action_state==LanPlayer.GroundActionState.NONE and absf(player.velocity.x)<0.1,"A supported slide still finishes normally")
	# Climb checks run before defense in the real physics loop.
	await reset(Vector2(0,1000))
	player.register_climbable(Rect2(-24,800,48,240))
	player.start_parry()
	Input.action_press(&"ui_up")
	await step(2)
	check(player.air_state!=LanPlayer.AirState.CLIMBING,"Climbing cannot steal an active defensive animation")
	release()
	await step(120)
	check(player.defense_state==LanPlayer.DefenseState.NONE,"Defense can finish after an upward input beside a ladder")
	# Dialogue freeze replaces the sprite, so cancel all old owners first.
	await reset(Vector2(0,1000))
	player.start_parry()
	player.set_input_frozen(true)
	await step(6)
	player.set_input_frozen(false)
	await step(90)
	check(player.defense_state==LanPlayer.DefenseState.NONE,"Freeze/resume cannot retain a defense whose animation was replaced")
	Input.action_press(&"jump")
	await step(3)
	check(player.air_state==LanPlayer.AirState.RISING,"Controls work after freeze interrupts defense")
	# A repeatable record replaces reliance on script exceptions or screenshots.
	await reset(Vector2(0,1000))
	var trace:=player.get_node("StateTrace")
	check(trace.report_count==0,"Normal handoffs do not generate contradiction reports")
	player.ground_action_state=LanPlayer.GroundActionState.SLIDE
	player.play_run()
	check(trace.contradiction()=="slide_owner_outlived_its_clip_or_support","Diagnostics recognize the exact Running plus Slide contradiction")
	trace.capture_now=true
	trace._process(0.0)
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(trace.last_report_path))
	check(report.reason=="manual_request" and report.current.ground_action=="SLIDE" and report.current.locomotion=="RUNNING" and report.current.clip=="run","One-shot capture saves the conflicting owners and visible animation")
	check(player.ground_action_state==LanPlayer.GroundActionState.SLIDE,"Diagnostics preserve the faulty state rather than silently reset it")
	player.reset_after_map_fall(Vector2(0,1000))
	release()
	world.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("LAN STATE HANDOFFS")
