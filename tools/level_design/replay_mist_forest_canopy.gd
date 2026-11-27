extends "../../tests/support/harness.gd"
## Replays the revised canopy route with ordinary player inputs and an in-memory save.
## The full run uses the west wall after three failed attempts at Trial 1's first gap.
## Use replay-mist-forest-canopy.ps1 to run headlessly or record a movie.

var forest: MistForest
var lan: LanPlayer
var warden: ForestCanopyChamber
var frame := 0
var age := 0
var state := 0
var room := 0
var probe := 0
var keys := ""
var retries := 0
var last_hit := -100
var hits: Array[String] = []
var seen: Array[String] = []
var fight_start := -1
var trace: FileAccess
var text_overlay: Label
var previous_pos := Vector2.ZERO
var jump_frame := -100

func run() -> void:
	var save := use_memory_progress()
	save.try_complete_fact(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED)
	var args := OS.get_cmdline_user_args()
	probe = args[0].to_int() if args.size() >= 1 else 0
	var frames := args[1].to_int() if args.size() >= 2 else 9350
	if probe < 0 or probe > 5 or frames < 1:
		push_error("Expected room 0–5 and a positive frame limit")
		quit(2)
		return
	var scene := load("res://scenes/levels/chapter_1/mist_forest.tscn") as PackedScene
	forest = scene.instantiate() as MistForest
	if probe:
		room = probe
		var chamber := get_chamber(room)
		var spawn := chamber.spawn_point
		if args.size() >= 5:
			spawn = Vector2(args[2].to_float(), args[3].to_float())
			state = args[4].to_int()
		(root.get_node("SceneTransition") as SceneTransitionService).set_scene_entry_position(chamber.position + spawn)
	root.add_child(forest)
	current_scene = forest
	lan = forest.player
	warden = get_chamber(5)
	if DisplayServer.get_name() != "headless":
		var layer := CanvasLayer.new()
		layer.layer = 30
		root.add_child(layer)
		text_overlay = Label.new()
		text_overlay.position = Vector2(920, 20)
		text_overlay.add_theme_font_size_override("font_size", 18)
		text_overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
		text_overlay.add_theme_constant_override("shadow_offset_x", 2)
		text_overlay.add_theme_constant_override("shadow_offset_y", 2)
		layer.add_child(text_overlay)
	for source in forest.find_children("*", "ForestPogoTarget", true, false):
		source.pogo_hit.connect(_hit)
	for source in forest.find_children("*", "ForestThornHazard", true, false):
		if is_instance_valid(source._surface):
			source._surface.rebounded.connect(_hit.bind(source))
	var output_dir := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var trace_path := ("user://" if output_dir.is_empty() else output_dir).path_join("inputs.tsv")
	trace = FileAccess.open(trace_path, FileAccess.WRITE)
	if trace == null:
		push_error("Could not open the replay trace: " + trace_path)
		quit(2)
		return
	trace.store_line("f\tr\ts\tx\ty\tvx\tvy\tair\tattack\tanimation\tvine\tkeys")
	previous_pos = lan.position
	for i in frames:
		await physics_frame
		frame += 1
		age += 1
		var p := lan.position
		if not seen.has(forest.current_room_name):
			seen.append(forest.current_room_name)
			print("ENTER ", frame, " ", forest.current_room_name, " ", p)
		if room > 0 and p.distance_to(previous_pos) > 32 and grounded():
			var chamber := get_chamber(room)
			if p.distance_to(chamber.current_checkpoint_global()) < 14:
				retries += 1
				print("RETRY ", frame, " ", room, "/", state, " ", previous_pos, " -> ", p)
				hits.clear()
				last_hit = -100
				if room == 1: go(20 if p.x > 2600 else 0)
				if room == 2: go(20 if p.x > 4100 else 0)
				if room == 3: go(20 if p.x > 6600 else (3 if p.y < -1200 else 0))
				if room == 4: go(40 if p.x > 9130 else (20 if p.x > 8500 else 0))
				if room == 5: go(0)
		previous_pos = p
		var requested := drive(p)
		trace.store_line("%d\t%d\t%d\t%.3f\t%.3f\t%.2f\t%.2f\t%d\t%d\t%s\t%s\t%s" % [frame,room,state,p.x,p.y,lan.velocity.x,lan.velocity.y,lan.air_state,lan.attack_state,lan.animated_sprite.animation,lan.vine.name if lan.vine else "",requested])
		set_keys(requested)
		if text_overlay:
			text_overlay.text = "%s · %s\n%05.1f 秒   输入 %s" % [MistForest.ROOM_TITLES.get(forest.current_room_name, "树冠困难线"), "连续回放" if not probe else "分房诊断", frame / 60.0, " ".join(keys.split("")) if not keys.is_empty() else "–"]
		if state == 99 and age > 106: break
	set_keys("")
	trace.close()
	expect_save_untouched()
	print("END ", frame, " ", room, "/", state, " ", lan.position, " | retries ", retries, " | visited ", seen)
	if state == 99:
		check(bool(warden.get("gate_open")) and forest.current_room_name == "VineAltar", "Warden defeated and reached the deer gate")
		if not probe:
			check(seen == ["MistEntry","MistFork","CanopyTrial1","CanopyTrial2","CanopyTrial3","CanopyTrial4","CanopyWarden","VineAltar"], "Continuous canopy route in order")
	quit(0 if state == 99 and failures == 0 else 1)

func get_chamber(n: int) -> ForestCanopyChamber:
	return forest.get_node("CanopyRoute/" + ("CanopyTrial%d" % n if n < 5 else "CanopyWarden")) as ForestCanopyChamber

func target(node: String) -> Node2D:
	return get_chamber(room).get_node(node) as Node2D

func _hit(object: Node2D) -> void:
	var hit := String(object.name)
	last_hit = frame
	hits.append(hit)
	print("POGO ", frame, " ", object.get_parent().name, "/", hit, " ", lan.position)

func go(next: int) -> void:
	print("STEP ", frame, " ", room, "/", state, " -> ", next, " ", lan.position)
	state = next
	age = 0

func next_room() -> void:
	room += 1
	hits.clear()
	last_hit = -100
	go(0)

func set_keys(next: String) -> void:
	var actions := {"A": &"ui_left", "D": &"ui_right", "W": &"jump", "U": &"instant_dash", "S": &"ui_down", "I": &"special_attack", "X": &"fast_fall"}
	for key in actions:
		if next.contains(key) == keys.contains(key): continue
		if next.contains(key): Input.action_press(actions[key])
		else: Input.action_release(actions[key])
	if next.contains("J") != keys.contains("J"):
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = next.contains("J")
		Input.parse_input_event(e)
	for input in {"E":KEY_E,"L":KEY_L,"K":KEY_K}:
		if next.contains(input) != keys.contains(input):
			var e := InputEventKey.new()
			e.physical_keycode = {"E":KEY_E,"L":KEY_L,"K":KEY_K}[input]
			e.keycode = e.physical_keycode
			e.pressed = next.contains(input)
			Input.parse_input_event(e)
	Input.flush_buffered_events()
	keys = next

func grounded() -> bool:
	return lan.air_state in [LanPlayer.AirState.GROUNDED,LanPlayer.AirState.LANDING,LanPlayer.AirState.ROLL_LANDING]

func aim(x: float, goal: float, dead := 4.0) -> String:
	if x < goal - dead: return "D"
	if x > goal + dead: return "A"
	return ""

func strike(p: Vector2, which: String, max_dx := 94.0, min_dy := 11.0, max_dy := 49.0) -> bool:
	var pos := target(which).global_position
	return absf(pos.x - p.x) < max_dx and (pos.y-p.y) >= min_dy and (pos.y-p.y) <= max_dy and lan.fast_fall.can_start(lan) and not keys.contains("J")

func drive(p: Vector2) -> String:
	match room:
		0: return opening(p)
		1: return wind_one(p)
		2: return wind_two(p)
		3: return vine_one(p)
		4: return vine_two(p)
		5: return finish_route(p)
	return ""

func opening(p: Vector2) -> String:
	match state:
		0:
			if p.x >= 2180:
				go(1)
				return "W"
			return "D"
		1:
			if grounded() and age > 35:
				go(2)
				return ""
			return "W"
		2:
			if p.x <= 1905:
				go(3)
				return ""
			return "AW"
		3:
			if p.y < -240:
				next_room()
				return "D"
			return aim(p.x, 1905) + ("W" if age <= 35 else "")
	return ""

func wind_one(p: Vector2) -> String:
	match state:
		0:
			if retries >= 3:
				go(30)
				return "A"
			if p.x > 1955:
				go(1)
				return "D"
			return "D" if p.y < -240 else aim(p.x, 1834) + ("W" if p.y >= -220 and age > 5 and age < 45 else "")
		1:
			if hits.has("Bud1"):
				go(2)
				return "DU" if p.y >= -279 and lan.can_start_aerial_dash() else "D"
			if strike(p,"Bud1",90,14,29) and lan.velocity.y >= 0: return "DSJ"
			return aim(p.x,1977)
		2:
			if p.x > 2170:
				go(3)
				return "D"
			if p.y < -265 and p.y > -275 and lan.can_start_aerial_dash(): return "DU"
			return "D"
		3:
			if hits.has("Bud2"):
				go(4)
				return ""
			if strike(p,"Bud2",94,12,25) and p.y > -291: return "DSJ"
			if p.y > -270 and lan.can_start_double_jump() and not keys.contains("W"): return "W"
			return aim(p.x,2205)
		4:
			if p.x > 2400:
				go(5)
				return "D"
			if frame-last_hit < 7 and not keys.contains("W") and lan.can_start_double_jump(): return "W"
			if p.y > -251 and lan.velocity.y > 0 and lan.can_start_aerial_dash(): return "DU"
			return aim(p.x,2222)
		5:
			if hits.has("Bud3"):
				go(6)
				return "D"
			if strike(p,"Bud3",94,13,44): return "DSJ"
			return aim(p.x,2437)
		6:
			if grounded() and p.x > 2680:
				go(20)
				return "D"
			if p.x < 2500 and p.y < -304 and p.y > -344 and lan.can_start_aerial_dash(): return "DU"
			if strike(p,"Bud4",90,12,43): return "DSJ"
			return aim(p.x,2750)
		20:
			if p.x > 2766 and grounded():
				go(21)
				return "DW"
			return "D"
		21:
			if p.x > 2920:
				go(22)
				return ""
			if p.x > 2798 and p.y > -373 and lan.can_start_aerial_dash(): return "DU"
			return "D"
		22:
			if hits.has("Bud5") and p.y < -392 and p.y > -430 and lan.can_start_aerial_dash():
				go(23)
				return "AU"
			if strike(p,"Bud5",90,9,46) and p.y > -380: return ("D" if p.x < 2965 else "A")+"SJ"
			if p.y > -335 and lan.can_start_double_jump() and not keys.contains("W"): return aim(p.x,2930)+"W"
			return "A"
		23:
			if lan.air_state == LanPlayer.AirState.WALL_SLIDING and not keys.contains("W"):
				if p.y < -660: return "A"
				jump_frame = frame
				if p.y < -647:
					go(26)
					return "AW"
				return "AW"
			if frame-jump_frame == 7 and p.y > -646 and lan.can_start_double_jump(): return "AW"
			return "A" + ("W" if keys.contains("W") and lan.air_state == LanPlayer.AirState.DOUBLE_JUMPING and lan.velocity.y < -25 and p.y > -636 else "")
		26:
			if p.x > 3099:
				go(24)
				return "D"
			if p.x > 2980 and p.y > -719 and p.y < -682 and lan.can_start_double_jump() and not keys.contains("W"): return "DW"
			return "D"
		24:
			if p.y < -457:
				return aim(p.x,3206,4)
			if p.x > 3288:
				go(25)
			if grounded() and p.x > 3240:
				go(27)
				return "DW"
			return "D"
		27:
			if p.x > 3294: go(25)
			return "D"
		25:
			if grounded() and p.x > 3320:
				next_room()
				return ""
			return aim(p.x,3345)
		30:
			if p.y < -1104:
				go(31)
				return aim(p.x,1630,3)
			if lan.air_state == LanPlayer.AirState.WALL_SLIDING and not keys.contains("W"):
				jump_frame = frame
				if p.y < -1055:
					go(31)
				return "AW"
			if frame-jump_frame == 8 and lan.can_start_double_jump(): return "AW"
			return "A" + ("W" if keys.contains("W") and lan.air_state == LanPlayer.AirState.DOUBLE_JUMPING and lan.velocity.y < -20 else "")
		31:
			if grounded() and p.y < -1090:
				go(32)
				return "DU"
			return aim(p.x,1630,3)
		32:
			if p.x > 2685:
				go(33)
			if p.x > 2140 and p.y < -730 and lan.can_start_aerial_dash(): return "DU"
			if p.x > 2070 and grounded() and lan.attack_state == LanPlayer.AttackState.INSTANT_DASH: return "ALK"
			if p.y > -640 and p.y < -545 and lan.can_start_double_jump(): return "DW"
			return "D" + ("W" if keys.contains("W") and lan.velocity.y < -20 else "")
		33:
			if grounded() and p.x > 2690:
				go(20)
			return aim(p.x,2750)
	return ""

func wind_two(p: Vector2) -> String:
	match state:
		0:
			if age <= 2 or age == 4: return ""
			if p.x > 3418 and grounded():
				go(1)
				return "DW"
			return "D"
		1:
			if hits.has("Hornet1"):
				go(2)
				return "D"
			if strike(p,"Hornet1",43,8,38): return "DSJ"
			if p.x > 3480 and p.x < 3540 and p.y < -509 and p.y > -536 and lan.can_start_aerial_dash(): return "DU"
			if p.y > -504 and p.x > 3474 and lan.can_start_double_jump() and not keys.contains("W"): return "DW"
			return "D" + ("W" if age < 12 else "")
		2:
			if p.x > 3799:
				go(3)
				return "D"
			if p.x < 3624 and p.y > -524 and lan.can_start_aerial_dash(): return "DU"
			return aim(p.x,3620)
		3:
			if grounded() and p.x > 4200:
				go(20)
				return "D"
			if not hits.has("Bud1") and p.x > 3805 and p.x < 3860 and strike(p,"Bud1",94,9,12): return "DSJ"
			if hits.has("Bud1") and p.x > 3808 and p.x < 3860 and p.y > -549 and p.y < -539 and lan.can_start_aerial_dash(): return "DU"
			if hits.has("Bud1") and p.x > 4009 and p.x < 4045 and p.y > -592 and lan.can_start_double_jump() and not keys.contains("W"): return "DW"
			if strike(p,"Hornet2",42,8,37): return "DSJ"
			if p.x > 3890 and p.x < 4145 and p.y < -595 and p.y > -658 and lan.can_start_aerial_dash(): return "DU"
			if ((p.x > 3800 and p.x < 3835 and p.y > -525 and not hits.has("Bud1")) or (p.x > 4040 and p.x < 4145 and p.y > -590 and not hits.has("Hornet2"))) and lan.can_start_double_jump(): return "DW"
			if not hits.has("Bud1") and p.x > 3817 and p.x < 3880: return aim(p.x,3818,3)
			if not hits.has("Bud1") and p.x > 3800: return "D"
			return "D" + ("W" if keys.contains("W") and lan.velocity.y < -70 else "")
		20:
			if age == 1 or age == 3: return ""
			if p.x >= 4580:
				go(21)
				return "DW"
			return "D"
		21:
			if p.x > 4739 and p.y > -591 and lan.can_start_aerial_dash():
				go(23)
				return "DU"
			if grounded() and p.x > 4758:
				go(22)
				return "D"
			return "D" + ("W" if age < 30 else "")
		22:
			if p.x > 4890:
				go(23)
			if p.x > 4840 and p.y > -586 and lan.can_start_aerial_dash(): return "DU"
			return "D"
		23:
			if p.x > 5325:
				go(24)
			if p.x > 5029 and strike(p,"SawPogo1",93,18,70): return ("A" if p.x>target("SawPogo1").global_position.x else "D") + "SJ"
			if p.x < 5030 and p.y > -528 and p.y < -497 and lan.can_start_double_jump(): return "DW"
			if strike(p,"BudEast",90,13,45): return "DSJ"
			if p.x > 5140 and p.y > -511 and lan.can_start_aerial_dash(): return "DU"
			if p.x > 5260 and p.y > -500 and lan.can_start_double_jump() and not keys.contains("W"): return "DW"
			return "D"
		24:
			if p.x > 5490:
				next_room()
				return "D"
			return "D"
	return ""

func vine_one(p: Vector2) -> String:
	match state:
		0:
			if p.x > 5605:
				go(1)
				return "DW"
			return "D"
		1:
			if p.y < -1175:
				go(2)
				return "D"
			return aim(p.x,5720) + ("W" if age < 40 else "")
		2:
			if grounded() and p.x > 5808:
				go(3)
				return ""
			return aim(p.x,5855)
		3:
			if age <= 2 or age == 4: return ""
			if p.x > 5922:
				go(4)
			return "D"
		4:
			if p.x > 6199:
				go(5)
			if p.x > 5930 and lan.can_start_aerial_dash(): return "DU"
			return "D"
		5:
			if hits.has("BudDrop1") and p.y > -1075 and p.y < -1041 and lan.velocity.y > 0 and lan.can_start_aerial_dash():
				go(6)
				return "AU"
			if strike(p,"BudDrop1",90,11,43) and not hits.has("BudDrop1"): return "DSJ"
			return aim(p.x,6224,3)
		6:
			if p.y > -755:
				go(7)
				return "DW"
			return "D" if p.y > -850 else aim(p.x,6005,3)
		7:
			if p.x > 6196:
				go(8)
			return "D" + ("W" if lan.velocity.y < -20 else "")
		8:
			if hits.has("BudDrop2"):
				go(9)
				return "D"
			if strike(p,"BudDrop2",95,12,50): return "DSJ"
			return aim(p.x,6230)
		9:
			if grounded() and p.x > 6630:
				go(20)
				return "D"
			if lan.vine: return "D" + ("W" if lan.vine_angle > 0.35 else "")
			if p.y < -730 and p.x < 6310 and lan.can_start_aerial_dash(): return "DU"
			if p.y > -715 and p.x > 6450 and lan.can_start_double_jump(): return "DW"
			return aim(p.x,6690) + ("W" if keys.contains("W") and lan.velocity.y < -25 else "")
		20:
			if grounded() and lan.oxygen.remaining < 96 and p.x < 6720: return ""
			if grounded() and p.x > 6690 and not keys.contains("W"): return "DW"
			if p.x > 6900:
				go(21)
				return "D"
			if p.y < -716 and p.x > 6740 and lan.can_start_aerial_dash(): return "DU"
			if lan.vine: return "DK"
			return "D" + ("W" if keys.contains("W") and lan.velocity.y < -20 else "")
		21:
			if p.x > 7681:
				next_room()
				return "D"
			if p.x > 7300 and p.x < 7410 and p.y < -763:
				return aim(p.x,7311,3) + "K"
			if p.x > 7285 and p.x < 7325 and p.y < -756 and lan.velocity.y < 230 and not lan.vine and not hits.has("reel"):
				go(22)
				return "A"
			if lan.vine: return "D" + ("W" if lan.vine_angle > 0.30 else "")
			if strike(p,"BudMid",92,12,53) and not hits.has("BudMid"): return "DSJ"
			if strike(p,"HornetExit",42,7,38): return "DSJ"
			if hits.has("BudMid") and p.x > 7054 and p.x < 7120:
				var saw_y := target("ThornSaw1").global_position.y
				if p.y < saw_y-49 and lan.can_start_aerial_dash(): return "DU"
				if p.y < -770 and lan.velocity.y > -155 and lan.can_start_double_jump() and not keys.contains("W"): return "W"
				return aim(p.x,7066,2)
			if hits.has("HornetExit") and p.x > 7450 and p.y < -669 and lan.can_start_aerial_dash(): return "DU"
			if p.x > 7324 and p.x < 7380 and p.y > -670 and p.y < -609 and lan.velocity.y > 0 and lan.can_start_double_jump() and not keys.contains("W") and not hits.has("baffle_jump"):
				hits.append("baffle_jump")
				return "DW"
			if hits.has("baffle_jump") and p.x < 7396: return "D"
			return "D" + ("W" if keys.contains("W") and lan.velocity.y < -75 else "")
		22:
			if lan.vine:
				if lan.vine_angle > 0.15 and p.x > 7222:
					hits.append("reel")
					go(21)
					return "DK"
				return "D"
			return aim(p.x,7203,5)
	return ""

func vine_two(p: Vector2) -> String:
	match state:
		0:
			if p.x > 7800:
				go(1)
				return "DW"
			return "D"
		1:
			if hits.has("Bud1"):
				go(2)
				return "D"
			if age < 10: return "DW"
			if strike(p,"Bud1"): return "DSJ"
			return aim(p.x,7905)
		2:
			if hits.has("Hornet1"):
				go(3)
				return "D"
			if p.y < -668 and p.x < 7950 and lan.can_start_aerial_dash(): return "DU"
			if strike(p,"Hornet1",44,9,38): return "DSJ"
			return aim(p.x,target("Hornet1").global_position.x-38)
		3:
			if hits.has("SawPogo1"):
				go(4)
				return "D"
			if strike(p,"SawPogo1",98,20,62): return "DSJ"
			return aim(p.x,8201)
		4:
			if p.x > 8525 and p.y < -660:
				go(5)
			if hits.has("Bud2"):
				return "DU" if p.y < -681 and lan.can_start_aerial_dash() else "D"
			if p.y > -684 and lan.velocity.y > 0 and p.x < 8350 and lan.can_start_aerial_dash(): return "DU"
			if not lan.aerial_dash_used: return aim(p.x,8200)
			if strike(p,"Bud2",98,8,48): return "DSJ"
			return aim(p.x,8380)
		5:
			if grounded() and p.x > 8542: go(20)
			return aim(p.x,8592)
		20:
			if p.x > 8630 and p.x < 8730 and grounded(): return "DW"
			if grounded() and p.x > 8730:
				go(21)
				return "D"
			return aim(p.x,8780) + ("W" if keys.contains("W") and lan.velocity.y < -20 else "")
		21:
			if p.x > 8880: go(22)
			if p.x > 8807 and lan.can_start_aerial_dash(): return "DU"
			return "D"
		22:
			if p.y < -1347 and p.x > 8940:
				go(23)
				return "D"
			if lan.air_state == LanPlayer.AirState.WALL_SLIDING and not keys.contains("W"):
				jump_frame = frame
				return ("D" if p.x > 8920 else "A") + "W"
			var spike := target("ChimneySpikeRight1") as ForestThornHazard
			if p.y < -922 and p.y > -1127 and not spike.is_retracted(): return aim(p.x,8961,2)
			if frame-jump_frame == 8 and lan.can_start_double_jump(): return "DW"
			return "D" + ("W" if keys.contains("W") and lan.air_state == LanPlayer.AirState.DOUBLE_JUMPING and lan.velocity.y < -25 else "")
		23:
			if grounded() and p.x > 9160: go(40)
			if lan.vine: return "D" + ("W" if lan.vine_angle > 0.35 else "")
			return aim(p.x,9200)
		40:
			if p.x > 9258 and (grounded() or lan.coyote_remaining > 0):
				go(41)
				return "DW"
			if age == 1 or age == 3: return ""
			return "D"
		41:
			if grounded() and p.x > 9325:
				go(42)
				return "D"
			return aim(p.x,9372)
		42:
			if p.x > 10070:
				next_room()
				return "D"
			if p.x > 10055 and grounded(): return "DW"
			if hits.has("Hornet2") and p.x > 9760 and p.x < 9920:
				var saw_y := target("SawPogo2").global_position.y
				if p.x > 9794 and p.y > -674 and p.y < -596 and p.y > saw_y + 82 and lan.can_start_aerial_dash():
					go(43)
					return "DU"
				if p.y > -617 and p.y < -574 and lan.can_start_double_jump() and not keys.contains("W"): return "W"
				return aim(p.x,9817,3) + ("W" if keys.contains("W") and lan.velocity.y < -35 else "")
			if lan.vine: return "D" + ("W" if lan.vine_angle > 0.35 else "")
			for name in ["Bud3","Hornet2","SawPogo2"]:
				if strike(p,name,42 if name == "Hornet2" else 93,15 if name != "SawPogo2" else 20,45 if name != "SawPogo2" else 66):
					return ("A" if target(name).global_position.x < p.x else "D")+"SJ"
			if hits.has("Bud3") and p.x > 9480 and p.x < 9541 and lan.can_start_aerial_dash():
				var saw_y := target("SawGate1").global_position.y
				if p.y < saw_y-46 or p.y > saw_y+96: return "DU"
				return aim(p.x,9510,4)
			if grounded() and (p.x < 9410 or p.x > 9955): return "DW"
			if p.x > 9840 and p.y > -625 and lan.can_start_double_jump(): return "DW"
			return "D" + ("W" if keys.contains("W") and lan.velocity.y < -40 else "")
		43:
			if p.x > 10085:
				next_room()
				return "D"
			if p.x > 10058 and grounded(): return "DW"
			return "D"
	return ""

func finish_route(p: Vector2) -> String:
	match state:
		0:
			if p.x >= 10255: go(1)
			return "D"
		1:
			if p.x >= 10344:
				go(2)
				return "DW"
			return "D"
		2:
			if p.x > 10815 and grounded(): go(3)
			if p.x < 10470 and p.y > -830: return aim(p.x,10420) + ("W" if keys.contains("W") and p.y > -640 else "")
			if lan.vine and p.x >= 10655: return "DK"
			if grounded() and p.x > 10440: return "DW"
			if lan.can_start_aerial_dash() and p.x > 10480 and p.y < -680: return "DU"
			return "D"
		3:
			if warden.get("gate_open"):
				fight_start = -1
				go(4)
			elif warden.get("combat_active"):
				if fight_start < 0: fight_start = frame - 1
				var combat_age := frame - fight_start
				if combat_age == 4 and grounded() and lan.can_afford_sword_wave(): return "DI"
				if combat_age == 132 and grounded() and lan.can_afford_sword_wave() and lan.attack_state == LanPlayer.AttackState.NONE: return "AI"
				var enemy_target: VineCombatEnemy
				var distance := INF
				for enemy: VineCombatEnemy in warden.get("_enemies"):
					if not is_instance_valid(enemy) or not enemy.is_targetable(): continue
					if enemy.role == VineCombatEnemy.Role.REEL and enemy.state in [VineCombatEnemy.State.WARNING,VineCombatEnemy.State.STRIKE]:
						return aim(p.x,clampf(enemy.aim.x + (155 if enemy.aim.x < 10965 else -155),10840,11120),6)
					if absf(enemy.tip.x-p.x) < distance:
						enemy_target = enemy
						distance = absf(enemy.tip.x-p.x)
				if enemy_target:
					var d := "D" if enemy_target.tip.x > p.x else "A"
					var move := aim(p.x,clampf(enemy_target.tip.x,10852,11102),18)
					if grounded() and lan.can_afford_sword_wave() and (combat_age - 4) % 32 == 0 and lan.attack_state == LanPlayer.AttackState.NONE: return d+"I"
					if enemy_target.state == VineCombatEnemy.State.WARNING and enemy_target.state_time > 0.72: return move+"K"
					if distance < 152 and (combat_age - 4) % 8 == 2: return d+"J" if signf(enemy_target.tip.x-p.x) == lan.facing_direction else d
					return move
			fight_start = -1
			return aim(p.x,10893,8) + ("E" if age % 20 == 8 and grounded() else "")
		4:
			if p.x >= 11890: go(5)
			if p.x >= 11096 and grounded(): return "DW"
			if p.x >= 11126 and p.y < -635 and lan.can_start_aerial_dash(): return "DU"
			if lan.vine: return "D" + ("K" if lan.vine_angle > 0.50 else "")
			return "D"
		5:
			if p.x >= 13580 and p.y >= -300:
				go(99)
				return ""
			if p.x > 12270 and p.x < 12450 and grounded(): return "DW"
			return "D"
	return ""
