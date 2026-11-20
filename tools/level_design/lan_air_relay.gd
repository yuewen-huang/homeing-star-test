extends "../../tests/support/harness.gd"

const LAN := preload("res://scenes/player/lan/lan_player.tscn")
const SPIKES := preload("res://assets/levels/chapter_2_underwater/cavern/environment/bell_city/trial_spike_rail.png")
const SPAWN := Vector2(109, 563)
const START := Rect2(32, 565, 166, 155)
const FINISH := Rect2(1055, 428, 193, 292)
const PIT := Rect2(198, 655, 857, 65)
const SCREENS := [Rect2(456, 448, 42, 272), Rect2(694, 0, 43, 389), Rect2(928, 426, 42, 294)]
const INK := Color("#101c28")
const COPPER := Color("#c19562")
const JADE := Color("#88e2c4")
const ROTOR_RADIUS := 29.0

class Rotor extends LanFastFall.PogoSurface:
	var rest: Vector2
	var sweep: Vector2
	var speed: float
	var phase: float
	var flash := 0.0

	func center() -> Vector2:
		return position + Vector2.DOWN * ROTOR_RADIUS

	func sample(seconds: float, step: float) -> void:
		position = rest + sweep * sin(seconds * speed + phase) - Vector2.DOWN * ROTOR_RADIUS
		flash = maxf(0.0, flash - step)
		queue_redraw()

	func _draw() -> void:
		var hub := Vector2.DOWN * ROTOR_RADIUS
		var teeth := PackedVector2Array()
		var turn := Time.get_ticks_msec() * 0.003
		for i in 48:
			var angle := TAU * i / 48.0 + turn
			var radius := ROTOR_RADIUS if i % 4 in [1, 2] else 22.0
			teeth.append(hub + Vector2.from_angle(angle) * radius)
		draw_colored_polygon(teeth, COPPER)
		draw_circle(hub, 17, INK)
		draw_arc(hub, 13, 0, TAU, 30, Color("#91a6a3"), 2.0, true)
		draw_circle(hub, 6, JADE if flash > 0.0 else COPPER)
		draw_line(Vector2(-18,0), Vector2(18,0), JADE if flash > 0.0 else Color("#f3ca87"), 2.5, true)

var world := Node2D.new()
var player: LanPlayer
var rotors: Array[Rotor] = []
var clock := 0.0
var finished := false
var attempt_hits: Array[int] = []
var failures_in_room := 0
var retry_flash := 0.0
var retry_at := Vector2.ZERO
var restart_held := false

func run() -> void:
	use_memory_progress()
	var quest_panel := root.get_node_or_null("QuestLog/QuestTracker") as CanvasLayer
	if quest_panel:
		quest_panel.hide()
	root.title = "归航星 · 悬重横井"
	root.add_child(world)
	current_scene = world
	world.draw.connect(paint)
	solid(START)
	solid(FINISH)
	for screen in SCREENS:
		solid(screen)
	solid(Rect2(0,0,16,720))
	solid(Rect2(1264,0,16,720))
	solid(Rect2(0,-20,1280,32))
	add_rotor(Vector2(329,593),Vector2(34,0),2.5,0.1)
	add_rotor(Vector2(606,573),Vector2(0,54),3.4,-0.7)
	add_rotor(Vector2(823,566),Vector2(40,0),2.8,2.0)
	player = LAN.instantiate() as LanPlayer
	player.world_min_x = 22
	player.world_max_x = 1258
	player.fallback_ground_y = 900
	player.position = SPAWN
	world.add_child(player)
	for child in player.get_children():
		if child is CanvasLayer:
			child.hide()
	physics_frame.connect(tick)
	if "--verify" in OS.get_cmdline_user_args():
		await verify()
	elif "--run-replay" in OS.get_cmdline_user_args():
		await replay(true)
		await step(35)
		await replay()
		await step(100)
		expect_save_untouched()
		finish("AIR RELAY FILM")

func solid(box: Rect2) -> void:
	var body := StaticBody2D.new()
	var bounds := RectangleShape2D.new()
	bounds.size = box.size
	var shape := CollisionShape2D.new()
	shape.shape = bounds
	body.position = box.get_center()
	body.add_child(shape)
	body.add_to_group(&"no_wall_slide")
	world.add_child(body)

func add_rotor(at: Vector2, sweep: Vector2, speed: float, phase: float) -> void:
	var rotor := Rotor.new()
	rotor.rest = at
	rotor.sweep = sweep
	rotor.speed = speed
	rotor.phase = phase
	rotor.rebound_height = 174.0
	rotor.follows_slash = true
	rotor.keeps_jump_buffer = true
	rotor.collision_layer = LanFastFall.POGO_LAYER
	rotor.collision_mask = 0
	rotor.sample(0.0,0.0)
	var shape := CollisionShape2D.new()
	var rim := RectangleShape2D.new()
	rim.size = Vector2(40,7)
	shape.shape = rim
	rotor.add_child(shape)
	rotor.add_to_group(&"pogo_target")
	rotor.rebounded.connect(bounce.bind(rotor))
	world.add_child(rotor)
	rotors.append(rotor)

func bounce(rotor: Rotor) -> void:
	player.aerial_dash_used = false
	rotor.flash = 0.32
	var index := rotors.find(rotor)
	attempt_hits.append(index)
	if OS.get_cmdline_user_args().has("--verify") or OS.get_cmdline_user_args().has("--run-replay"):
		print("BOUNCE ", index, " at ", player.position, " time ", clock)

func tick() -> void:
	var dt := world.get_physics_process_delta_time()
	retry_flash = maxf(0.0,retry_flash-dt)
	var wants_restart := Input.is_physical_key_pressed(KEY_R)
	if wants_restart and not restart_held:
		restart(false)
	restart_held = wants_restart
	if not finished:
		var body := CombatHitQuery.hurtbox_rect(player)
		var clipped := body.intersects(PIT) or player.position.y > 700
		for screen: Rect2 in SCREENS:
			clipped = clipped or body.intersects(screen)
		for rotor in rotors:
			var hub := rotor.center()
			var closest := hub.clamp(body.position,body.end)
			clipped = clipped or closest.distance_squared_to(hub) < pow(ROTOR_RADIUS-2.0,2)
		if clipped:
			retry_at = body.get_center()
			if "--verify" in OS.get_cmdline_user_args():
				print("RETRY at ",player.position," time ",clock)
			restart(true)
		elif player.position.x > FINISH.position.x + 24.0 and player.is_on_floor():
			finished = true
			print("RELAY CLEARED ",attempt_hits," time ",clock)
		clock += dt
		for rotor in rotors:
			rotor.sample(clock,dt)
	world.queue_redraw()

func restart(hit: bool) -> void:
	if hit:
		failures_in_room += 1
		retry_flash = 0.28
	player.reset_after_map_fall(SPAWN)
	attempt_hits.clear()
	finished = false
	clock = 0.0

func paint() -> void:
	world.draw_rect(Rect2(0,0,1280,720),INK)
	for i in 8:
		var x := float(i * 182 - 5)
		world.draw_rect(Rect2(x,66,118,590),Color("#172838"))
		world.draw_rect(Rect2(x+8,76,102,580),Color("#20394a"))
		world.draw_line(Vector2(x+9,172),Vector2(x+109,104),Color("#2b4655"),4)
		world.draw_line(Vector2(x+9,276),Vector2(x+109,208),Color("#2b4655"),4)
	world.draw_rect(Rect2(0,0,1280,22),Color("#2a3f4a"))
	for box in [START, FINISH]:
		world.draw_rect(box,Color("#263b47"))
		world.draw_rect(Rect2(box.position,Vector2(box.size.x,15)),Color("#6e8489"))
		world.draw_line(box.position,Vector2(box.end.x,box.position.y),Color("#b7c6c3"),3)
	for box: Rect2 in SCREENS:
		world.draw_rect(box,Color("#202a30"))
		world.draw_rect(box.grow(-6),Color("#5d5044"))
		for y in range(int(box.position.y)+16,int(box.end.y)-9,23):
			world.draw_line(Vector2(box.position.x+5,y),Vector2(box.end.x-5,y+11),COPPER,2)
		if box.position.y==0.0:
			world.draw_set_transform(Vector2(box.end.x,box.end.y), PI)
			world.draw_texture_rect(SPIKES,Rect2(0,0,box.size.x,14),false)
			world.draw_set_transform(Vector2.ZERO)
		else:
			world.draw_texture_rect(SPIKES,Rect2(box.position,Vector2(box.size.x,14)),false)
		world.draw_rect(box,Color("#c79b6c"),false,2)
	for i in 17:
		var width := PIT.size.x/17.0
		world.draw_texture_rect(SPIKES,Rect2(PIT.position.x+i*width,PIT.position.y,width,20),false)
	world.draw_rect(Rect2(PIT.position.x,PIT.position.y+19,PIT.size.x,60),Color("#322522"))
	for rotor in rotors:
		var begin := rotor.rest - rotor.sweep
		var end := rotor.rest + rotor.sweep
		world.draw_line(begin,end,Color("#0c171f"),13,true)
		world.draw_line(begin,end,Color("#7e7561"),4,true)
		for at in [begin,end]:
			world.draw_circle(at,5,COPPER)
	var marker := Vector2(1160,388)
	world.draw_arc(marker,24,PI,TAU,24,JADE if finished else COPPER,3,true)
	world.draw_line(marker+Vector2(-24,0),marker+Vector2(-24,39),COPPER,4)
	world.draw_line(marker+Vector2(24,0),marker+Vector2(24,39),COPPER,4)
	world.draw_circle(marker,7,JADE if finished else Color("#f3ca87"))
	if retry_flash > 0.0:
		world.draw_arc(retry_at,12+(0.28-retry_flash)*90.0,0,TAU,22,Color(1,0.43,0.28,retry_flash/0.28),2,true)

func step(frames: int) -> void:
	for i in frames:
		await physics_frame

func input(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)

func steer(x: float, deadzone := 6.0) -> void:
	input(&"ui_right", x-player.position.x > deadzone)
	input(&"ui_left", player.position.x-x > deadzone)

func hit_rotor(index: int) -> bool:
	var rotor := rotors[index]
	var failed_before := failures_in_room
	var hit_before := attempt_hits.size()
	for i in 155:
		if failures_in_room != failed_before:
			return false
		if attempt_hits.size() > hit_before:
			input(&"fast_fall",false)
			return attempt_hits.back() == index
		var delta := rotor.position - player.position
		steer(rotor.position.x)
		var strike := player.attack_state == LanPlayer.AttackState.NONE and absf(delta.x) < 27 \
			and delta.y > 8 and delta.y < 80 and player.velocity.y > -30.0
		input(&"fast_fall",strike)
		await step(1)
	input(&"fast_fall",false)
	return false

func dash_right() -> void:
	input(&"ui_left",false)
	input(&"ui_right",true)
	input(&"instant_dash",true)
	await step(1)
	input(&"instant_dash",false)
	await step(18)

func replay(clip_ceiling := false) -> void:
	input(&"ui_right",false)
	input(&"ui_left",false)
	input(&"fast_fall",false)
	await step(12)
	restart(false)
	var failures_before := failures_in_room
	input(&"ui_right",true)
	await step(16)
	input(&"jump",true)
	var first := await hit_rotor(0)
	input(&"jump",false)
	check(first, "First rotor: leave the deck and catch a moving striking edge")
	if not first: return
	input(&"ui_right",true)
	for i in 36:
		if player.position.y < 435.0: break
		await step(1)
	await dash_right()
	check(player.position.x > SCREENS[0].end.x, "High dash clears the rising bulkhead")
	if failures_in_room != failures_before: return
	var second := await hit_rotor(1)
	check(second, "Brake and strike the vertical rotor on descent")
	if not second: return
	input(&"ui_right",true)
	for i in 18:
		if player.position.y < (428.0 if clip_ceiling else 466.0): break
		await step(1)
	await dash_right()
	if clip_ceiling:
		input(&"ui_right",false)
		check(failures_in_room == failures_before+1 and retry_at.x > 660.0 and player.position.x < START.end.x, "Late dash hits hanging blades and returns directly to the starting deck")
		return
	check(player.position.x > SCREENS[1].end.x, "Early low dash passes under the hanging blades")
	if failures_in_room != failures_before: return
	var third := await hit_rotor(2)
	check(third, "Third rotor catches a landing that would otherwise hit the pit")
	if not third: return
	input(&"ui_right",true)
	for i in 36:
		if player.position.y < 411.0: break
		await step(1)
	await dash_right()
	steer(1151.0)
	await step(49)
	input(&"ui_right",false)
	check(finished and failures_in_room == failures_before, "Reach the far deck without resting mid-room")

func verify() -> void:
	await replay(true)
	await replay()
	restart(false)
	await step(8)
	var failed_before := failures_in_room
	input(&"ui_right",true)
	await step(150)
	input(&"ui_right",false)
	check(failures_in_room > failed_before and not finished, "Walking into the pit retries immediately")
	expect_save_untouched()
	finish("AIR RELAY")
