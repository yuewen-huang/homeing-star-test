extends "../../../support/harness.gd"
## Replay the two routes with normal player inputs and in-memory progress. Use --upper for the guardian route.
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
	return level.works.room_point(id,x,y)

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

func hear_fragment(id: String) -> void:
	if not route_ok:
		return
	for i in 850:
		if player.input_frozen:
			await advance_dialogue()
		if level.chapter_story.save.has_completed(level.chapter_story._heard_fact(id)):
			return
		if i%30==0:
			await tap(KEY_E)
		await physics_frame
	route_ok=false
	print("NO ECHO ",id," ",player.position)


func run() -> void:
	use_memory_progress()
	level=load("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn").instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	await frames(10)
	if level.works==null:
		check(false,"map ready")
		finish("CITY")
		return
	for stop in [["quay",384,519],["quay",648,519],["fork",69,520]]:
		await waypoint(stop)
	if "--upper" in OS.get_cmdline_user_args():
		await upper()
	else:
		await lower()
	check(route_ok,"Route through the room graph")
	expect_save_untouched()
	finish("CITY")

func upper() -> void:
	for v in [["fork",185,436],["fork",282,358],["fork",195,279],["fork",257,199],["fork",152,118],["fork",140,45,"climb"],["teeth",140,484,"climb"],["teeth",185,485],["teeth",202,485]]:
		await waypoint(v)
	if not route_ok:
		return
	for v in [[290,436],[444,381],[603,328]]:
		var goal := room_position("teeth",v[0],v[1])
		if player.air_state==player.AirState.GROUNDED:
			await tap(KEY_W)
		for i in 185:
			set_action("ui_right",player.position.x<goal.x-3)
			set_action("ui_left",player.position.x>goal.x+3)
			if i==19 or (player.velocity.y>0 and player.position.y>goal.y-45 and player.position.x<goal.x-50 and not player.double_jump_used):
				await tap(KEY_W)
			if absf(player.position.x-goal.x)<34 and player.position.y<goal.y:
				await tap(KEY_X)
				break
			await physics_frame
		var count:int=level.works.ringing.size()
		for i in 65:
			if level.works.ringing.size()>count or level.works.opened.chain_gate:
				break
			await physics_frame
	release_inputs()
	check(level.works.opened.chain_gate,"Three hammers struck without landing")
	set_action("ui_right",true)
	await frames(4)
	await tap(KEY_U)
	await frames(30)
	release_inputs()
	await move_to("bolt",70,520)
	if not route_ok:
		return
	await frames(8)
	await tap(KEY_D)
	send_key(KEY_D,true)
	await frames(14)
	send_key(KEY_S,true)
	await frames(12)
	await frames(20)
	send_key(KEY_S,false)
	await frames(95)
	send_key(KEY_D,false)
	await move_to("bolt",460,520)
	await move_to("bolt",487,250,"climb")
	set_action("ui_up",true)
	await frames(75)
	release_inputs()
	send_key(KEY_D,true)
	await tap(KEY_W)
	await frames(48)
	send_key(KEY_D,false)
	if not route_ok:
		return
	for v in [["bolt",565,520],["bolt",764,520]]:
		await waypoint(v)
	if not route_ok:
		return
	for i in 260:
		if level.works.opened.reed_gate:
			break
		var dart_in_range:bool=level.works.bolt_dir<0 and level.works.bolt_source.position.x-player.position.x<70
		if dart_in_range:
			await tap(KEY_K)
		await physics_frame
	check(level.works.opened.reed_gate,"Parry opens reed door")
	if not level.works.opened.reed_gate:
		return
	await move_to("tide",267,485)
	if not route_ok:
		return
	for i in 1900:
		if level.works.spring>2.1:
			break
		await physics_frame
	send_key(KEY_D,true)
	await frames(10)
	await tap(KEY_U)
	await frames(131)
	send_key(KEY_D,false)
	check(level.works.save.has_completed(level.works.RACE),"Floodgate crossed in time")
	if not level.works.save.has_completed(level.works.RACE):
		return
	await move_to("keeper",612,520)
	if not route_ok:
		return
	var boss=level.bronze_toad
	for i in 27000:
		if boss.defeated:
			break
		set_action("ui_right",true)
		if absf(player.position.x-(boss.position.x+34))>120 and i%100==1:
			await tap(KEY_U)
		if i%12==1:
			await tap(KEY_J)
		if boss.ball==boss.Ball.GOLD and i%20==5:
			await tap(KEY_K)
		await physics_frame
	release_inputs()
	check(boss.defeated,"Defeat the guard with Lan's attacks")
	if boss.defeated:
		await move_to("door",416,520)
		await tap(KEY_E)
		await frames(14)
		await advance_dialogue()
		check(level.chapter_story.save.has_completed(level.chapter_story.PASSAGE),"Open the cicada door from above")

func lower() -> void:
	for v in [["fork",880,520],["bell",45,518],["bell",66,448],["bell",166,505,"swim"],["bell",345,517],["bell",332,450]]:
		await waypoint(v)
	if not route_ok:
		return
	await tap(KEY_E)
	await frames(90)
	await advance_dialogue()
	check(level.resonance.awake,"Ring bell by hand")
	for v in [["bell",453,389],["bell",586,323],["bell",728,263],["bell",850,209]]:
		await waypoint(v)
	await hear_fragment("outer_waterway")
	if route_ok:
		await wait_ebb()
	for v in [["bell",200,510,"swim"],["sump",166,153,"swim"],["sump",275,242,"swim"],["sump",279,407,"swim"],["sump",290,468,"swim"],["sump",85,464,"swim"]]:
		await waypoint(v)
	await hear_fragment("vault")
	if route_ok:
		await wait_ebb()
	for v in [["sump",290,464,"swim"],["sump",440,470,"swim"],["sump",800,470,"swim"],["pipe",285,466,"swim"],["pipe",660,466,"swim"],["grotto",416,456,"swim"],["grotto",880,453,"swim"],["grotto",852,377,"swim"]]:
		await waypoint(v)
	if route_ok:
		set_action("ui_up",true)
		await frames(140)
		release_inputs()
		await frames(8)
		await tap(KEY_W)
		await move_to("grotto",854,230,"climb")
	await hear_fragment("archive")
	if not route_ok:
		return
	for v in [["grotto",748,297],["grotto",664,451,"swim"],["grotto",435,475,"swim"],["grotto",144,463,"swim"],["grotto",148,269,"swim"],["grotto",150,109,"swim"],["beast",150,492,"swim"],["beast",259,516]]:
		await waypoint(v)
	if not route_ok:
		return
	await move_to("beast",560,520)
	var lion=level.stone_lion
	for i in 900:
		if lion.hammer_inspected:
			break
		if i%20==0:
			await tap(KEY_J)
		if is_instance_valid(lion._hammer_dialogue):
			await tap(KEY_E)
		await physics_frame
	check(lion.hammer_inspected,"Test the counterweight with a sword strike")
	await move_to("beast",320,520)
	await tap(KEY_E)
	await move_to("beast",582,520)
	for i in 1250:
		if lion.broken:
			break
		if lion.state==lion.State.CHARGE and lion.position.distance_to(player.position)<275:
			await tap(KEY_W)
		await physics_frame
	check(lion.broken,"Lure the stone lion into the counterweight")
	if not lion.broken:
		return
	await move_to("beast",805,520)
	await hear_fragment("sealed_street")
	await move_to("beast",842,520)
	await tap(KEY_E)
	check(level.works.opened.side_gate,"Acquire tidebell tongue and open the side shaft")
	for v in [["side",260,450],["side",440,377],["side",594,301],["side",760,226],["side",867,148],["side",780,73],["door",770,511,"climb"],["door",431,520]]:
		await waypoint(v)
	if not route_ok:
		return
	await tap(KEY_E)
	await frames(15)
	await advance_dialogue()
	check(level.chapter_story.save.has_completed(level.chapter_story.PASSAGE) and not level.bronze_toad.defeated,"Open the shared door while the guard lives")
	await frames(78)
	await tap(KEY_E)
	var enc  :=  level.twin_fish_encounter
	check(player.position.x>enc.arena.position.x,"Step through the open arch into the west landing")
	for i in 1800:
		if enc.battle_ready:
			break
		set_action("ui_right",not enc.engaged)
		if player.input_frozen and not enc.engaged:
			await advance_dialogue()
		await physics_frame
	release_inputs()
	check(enc.battle_ready,"Reach the formal Twin Fish fight")
	if enc.battle_ready:
		var reduced  :=  true
		for fish_body in [enc.fish.xuan,enc.fish.zhao]:
			var stats = fish_body.combat_stats
			print("FISH HEALTH ",stats.health,"/",stats.max_health)
			reduced = reduced and absf(float(stats.health)/stats.max_health-0.8)<0.01
		check(reduced,"Both fish begin at eighty percent with the tidebell tongue")



func wait_ebb() -> void:
	release_inputs()
	for i in 2400:
		if level.tide.surge_age()>5.55 and level.tide.surge_age()<6.45:
			break
		await physics_frame
