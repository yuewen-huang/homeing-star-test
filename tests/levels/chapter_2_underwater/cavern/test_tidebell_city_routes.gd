extends "../../../support/harness.gd"
## Exercise the two fork entrances.
var level:SunkenCavern
var player:LanPlayer
var route_ok := true

func frames(n:int) -> void:
	for i in n:
		await physics_frame

func send_key(k:Key,v:bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode=k
	ev.physical_keycode=k
	ev.pressed=v
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func tap(k:Key) -> void:
	send_key(k,true)
	await frames(2)
	send_key(k,false)
	await frames(2)

func set_action(id:String,v:bool) -> void:
	if v and not Input.is_action_pressed(id):
		Input.action_press(id)
	if not v and Input.is_action_pressed(id):
		Input.action_release(id)

func release_inputs() -> void:
	for id in ["ui_left","ui_right","ui_up","ui_down","jump","fast_fall","parry","instant_dash"]:
		set_action(id,false)

func advance_dialogue() -> void:
	release_inputs()
	for i in 52:
		if not player.input_frozen:
			break
		await tap(KEY_E)
		await frames(10)

func room_position(id:String,x:float,y:float) -> Vector2:
	return level.vector(level.works.settings.rooms[id]) + Vector2(x*1.5,y*1.25)

func move_to(id:String,x:float,y:float,mode := "land",limit := 950) -> bool:
	if not route_ok:
		return false
	var goal := room_position(id,x,y)
	var previous_position := player.position
	var blocked_frames := 0
	for i in limit:
		var d := goal-player.position
		if absf(d.x)<16 and absf(d.y)<25 and (mode!="land" or player.air_state in [player.AirState.GROUNDED,player.AirState.LANDING] or absf(d.y)<4):
			release_inputs()
			print("AT ",id," ",x," ",y," ",player.position)
			return true
		if player.input_frozen:
			await advance_dialogue()
		set_action("ui_left",d.x < (-22 if mode=="climb" else -6))
		set_action("ui_right",d.x>(22 if mode=="climb" else 6))
		if previous_position.distance_to(player.position)<0.4:
			blocked_frames+=1
		else:
			blocked_frames=0
		previous_position=player.position
		var swimming := mode == "swim"
		var grounded := player.air_state == player.AirState.GROUNDED
		var rise := swimming and d.y < -10 and (not grounded or i % 12 > 4)
		set_action("ui_up", rise or mode == "climb")
		set_action("ui_down", swimming and player.is_in_deep_water() and d.y > 12)
		var reach_ledge := d.y < -31 and (not swimming or player.swim.floating or grounded)
		var clear_step := blocked_frames > 12 and absf(d.x) > 20 and mode == "land"
		var jump := mode != "climb" and (reach_ledge or clear_step) and i % 55 in [1,23]
		var push_off_bottom := swimming and player.is_in_deep_water() and grounded and i % 23 == 0
		set_action("jump", jump or push_off_bottom)
		await physics_frame
	release_inputs()
	route_ok=false
	print("BLOCK ",id," ",goal," actual ",player.position," state ",player.air_state," wet ",player.is_in_deep_water()," deaths ",level.drowned_count)
	return false

func waypoint(v:Array) -> void:
	await move_to(v[0],v[1],v[2],v[3] if v.size()>3 else "land")

func run() -> void:
	var save := use_memory_progress()
	save.try_complete_fact(&"sunken_cavern_bell_awake")
	save.try_complete_fact(&"story_c2_revised_cavern_bell")
	level=load("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn").instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	await frames(10)
	if level.works==null:
		check(false,"map ready")
		finish("CITY")
		return
	await fork_doors()
	check(route_ok,"Route through the room graph")
	expect_save_untouched()
	finish("CITY")

func fork_doors() -> void:
	for stop in [["quay",384,519],["quay",648,519],["fork",69,520],["fork",848,520]]:
		await waypoint(stop)
	if not route_ok: return
	set_action("ui_right",true)
	await frames(45)
	release_inputs()
	var east_wall := level.get_node("Districts/fork/Geometry/Rock/Fork9") as Control
	var distance := east_wall.global_position.x - player.global_position.x
	check(level.current_space == "fork" and distance > 0 and distance < 32, "Walking past the pavilion stops at the east wall")
	await move_to("fork",588,520)
	if not route_ok: return
	await tap(KEY_E)
	await frames(44)
	check(level.current_space == "listening_entry", "Enter the listening canal through its door")
	await tap(KEY_E)
	await frames(44)
	check(level.current_space == "fork", "Return through the listening door")
	await move_to("fork",365,520)
	await move_to("fork",365,430)
	await move_to("fork",260,343)
	if not route_ok: return
	set_action("ui_left",true)
	for i in 120:
		if level._crossing_door: break
		await physics_frame
	release_inputs()
	await frames(44)
	check(level.upper_route.room_at(player.position) == level.upper_route.rooms[0], "Cross the upper workshop threshold")
