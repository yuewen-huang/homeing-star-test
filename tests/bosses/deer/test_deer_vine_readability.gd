extends "../../support/harness.gd"
## Production forest, ordinary player and real inputs; no save writes or invulnerability.
var room: Chapter1DeerBossRoom
var deer: Node2D
var lan: LanPlayer
var events: Array[Dictionary] = []
var output := ""

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K, KEY_J, KEY_L, KEY_W]: key(code, false)
	for action in [&"ui_left", &"ui_right"]: Input.action_release(action)

func walk_to(x: float, tolerance := 4.0) -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	if absf(lan.position.x-x)>tolerance:
		Input.action_press(&"ui_right" if x>lan.position.x else &"ui_left")

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func prepare(boss_x: float, player_x: float, difficulty: int) -> void:
	release()
	deer.restart_duel()
	deer.position=Vector2(boss_x,555)
	deer.manual_control=false
	deer.wait_left=999
	lan.reset_after_map_fall(Vector2(player_x,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(difficulty)

func punish(label: String) -> void:
	var hp: int=deer.combat_stats.health
	var beginning: float=deer.opening
	var captured := false
	var presses := 0
	for frame in 150:
		key(KEY_J,false)
		if deer.opening<=0: break
		deer.wait_left=999
		walk_to(deer.position.x-signf(deer.position.x-lan.position.x)*95,8)
		lan.facing_direction=signf(deer.position.x-lan.position.x)
		if absf(deer.position.x-lan.position.x)<175 and frame%12==0:
			key(KEY_J,true)
			presses+=1
		if not captured and deer._recovery_age>=.25:
			captured=true
			check(deer.authored_body.clip!=&"idle_ING",label+" has a distinct authored recovery pose")
			await capture(label+"_punish")
		await physics_frame
	release()
	deer.wait_left=999
	var damage: int=hp-deer.combat_stats.health
	check(damage>0,label+" real J reaches the boss during the natural opening")
	events.append({"route":label,"opening":beginning,"punish_damage":damage,"presses":presses,"player_hp":lan.combat_stats.health})
	await wait_frames(8)

func sweep_route(side: float) -> void:
	prepare(1280,1280+side*185,BattleAssistSettingsService.Difficulty.HARD)
	deer.pressure.selected=1
	deer.start_phrase(1)
	var pressed := false
	for frame in 220:
		key(KEY_K,false)
		if deer.move==&"sweep" and deer.age>=.52 and not pressed:
			key(KEY_K,true)
			pressed=true
		await physics_frame
		if deer.opening>0: break
	check(lan.combat_stats.health==100,"Sweep is manually parried before the recovery")
	check(is_equal_approx(deer.opening,.85),"Ordinary recovery keeps its 0.85 action seconds")
	await punish("sweep_right" if side>0 else "sweep_left")

func rain_route(delay: float, difficulty: int) -> void:
	prepare(1110,1390,difficulty)
	deer.pressure.selected=3
	deer.start_phrase(3)
	var wave := 0
	var go_at := INF
	var target_x := lan.position.x
	var checked_peaks := {}
	var impacts := {}
	var last_opening := 0.0
	for frame in 700:
		if deer.arena.wave_count!=wave:
			wave=deer.arena.wave_count
			go_at=deer.age+delay
			# Respond to the newly painted floor lane after a fixed human-scale delay.
			# The midpoint is visible; this does not teleport or alter the player.
			var side := signf(deer._sky_return_x-lan.position.x)
			if is_zero_approx(side): side=1
			target_x=clampf(lan.position.x+side*105,deer.world_min_x+55,deer.world_max_x-55)
		if deer.move==&"sky_cast" and deer.age>=go_at:
			walk_to(target_x)
		for h in deer.arena.hazards:
			if not h.falling: continue
			if h.armed: impacts[h.serial]=true
			if not checked_peaks.has(h.serial) and absf(float(h.age)-float(h.delay)+.10)<.009:
				checked_peaks[h.serial]=true
				check(deer.arena.cast_warning.visible,"Rain release %d retains its own gold peak"%h.serial)
				events.append({"beat":h.serial,"boss_age":deer.age,"flash_visible":deer.arena.cast_warning.visible,"flash_frame":deer.arena.cast_warning.frame,"player_x":lan.position.x})
				await capture("rain_gold_%d_%d"%[difficulty,h.serial])
		await physics_frame
		if deer.opening>0:
			last_opening=deer.opening
			break
		if lan.combat_stats.health<=0: break
	release()
	check(checked_peaks.size()==5,"All five releases including both crossing ranks have visible peaks")
	check(impacts.size()==5,"All five original attacks still execute")
	check(lan.combat_stats.health==100,"Walking to the warned gap after %.2fs avoids all five impacts"%delay)
	check(deer.arena.hazards.is_empty() and is_equal_approx(last_opening,1.8),"Rain fully retires before its unchanged 1.8-second opening")
	events.append({"route":"rain","difficulty":difficulty,"reaction_delay":delay,"hp":lan.combat_stats.health,"x":lan.position.x,"boss_x":deer.position.x})
	if last_opening>0: await punish("rain_%d"%difficulty)

func run() -> void:
	use_memory_progress()
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	room.encounter._spawn_phase(3,1110)
	room.encounter.start()
	deer=room.deer
	lan=room.player
	await sweep_route(1)
	await rain_route(.18,BattleAssistSettingsService.Difficulty.HARD)
	if not "--movie" in OS.get_cmdline_user_args():
		await sweep_route(-1)
		await rain_route(.18,BattleAssistSettingsService.Difficulty.NIGHTMARE)
	release()
	if not output.is_empty(): FileAccess.open(output.path_join("readability_events.json"),FileAccess.WRITE).store_string(JSON.stringify(events,"\t"))
	print("READABILITY_EVENTS "+JSON.stringify(events))
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER VINE READABILITY")
