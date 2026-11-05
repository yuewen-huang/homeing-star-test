extends "../../support/harness.gd"
## Probe the user's immediate-parry/jump/leave strategy, not just scripted success.
var room: BossDevelopmentRoom
var deer: Node2D
var lan: LanPlayer
var hits: Array[Dictionary] = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K,KEY_W,KEY_J]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func trial(side: int, policy: String) -> Dictionary:
	release()
	room._combat_result=""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.wait_left=999
	deer.position=Vector2(820 if side<0 else 360,555)
	lan.reset_after_map_fall(Vector2(380 if side<0 else 800,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	lan.facing_direction=-side
	for f in 12: await physics_frame
	hits.clear()
	deer.start_phrase()
	var rushed := false
	var swept := false
	var jumped := false
	var landed := false
	var jump_frame := -1
	var jumped_at := ""
	var seen_end := false
	var first_hit := -1.0
	var begin_hp: int = deer.combat_stats.health
	var end_gap := 0.0
	var punish_frames := 0
	for f in 650:
		key(KEY_K,false)
		key(KEY_J,false)
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		if not rushed and deer.move==&"rush" and deer.age>=.68 and absf(deer.position.x-lan.position.x)<295:
			rushed=true
			key(KEY_K,true)
		var parried := hits.any(func(h): return h.move==&"rush" and h.result==CombatHitResult.Type.PARRY_SUCCESS)
		if not jumped:
			if policy=="read": key(KEY_W,deer.move==&"vine_return" and deer.age>=deer.VINE_RELEASE-.23)
			elif parried: key(KEY_W,f%8<4) # Re-request until the existing defense recovery permits takeoff.
			if lan.air_state!=LanPlayer.AirState.GROUNDED:
				jumped=true
				jump_frame=f
				jumped_at="%s:%.3f" % [deer.move,deer.age]
		elif f-jump_frame<30: key(KEY_W,true)
		else: key(KEY_W,false)
		if jumped and f-jump_frame>5 and lan.air_state==LanPlayer.AirState.GROUNDED: landed=true
		if policy!="read" and parried and deer.opening<=0:
			var walk_side := side if policy=="leave_forward" else -side
			Input.action_press(&"ui_right" if walk_side>0 else &"ui_left")
		if policy=="read" and not swept and deer.move==&"sweep" and deer.age>=.48:
			key(KEY_K,true)
			swept=true
		if deer.opening>0:
			if not seen_end: end_gap=absf(deer.position.x-lan.position.x)
			seen_end=true
			punish_frames+=1
			var gap: float=deer.position.x-lan.position.x
			if absf(gap)>140: Input.action_press(&"ui_right" if gap>0 else &"ui_left")
			else:
				lan.facing_direction=signf(gap)
				if punish_frames%12==1: key(KEY_J,true)
		await physics_frame
		if first_hit<0 and deer.combat_stats.health<begin_hp: first_hit=punish_frames/60.0
		if seen_end and deer.opening<=0:
			deer.wait_left=999
			break
	release()
	var row := {"side":side,"policy":policy,"player_hp":lan.combat_stats.health,"jump":jumped_at,"landed":landed,"gap_at_recovery":end_gap,"first_punish_seconds":first_hit,"punish_damage":begin_hp-deer.combat_stats.health,"hits":hits.duplicate(true)}
	print("VINE ESCAPE "+JSON.stringify(row))
	return row

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_duel_adapter.gd"): room.select_boss(i)
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	deer=room.adapter.boss
	lan=room.player
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): hits.append({"move":deer.move,"age":deer.age,"result":result}))
	var rows: Array[Dictionary]=[]
	for side in [-1,1]:
		var close_damage := 0
		for policy in ["read","leave_forward","leave_back"]:
			var row := await trial(side,policy)
			rows.append(row)
			check(row.landed and row.hits.any(func(h): return h.move==&"rush" and h.result==CombatHitResult.Type.PARRY_SUCCESS),"Route uses a real rush parry and jump landing")
			if policy=="read":
				close_damage=row.punish_damage
				check(row.player_hp==100 and row.hits.any(func(h): return h.move==&"sweep" and h.result==CombatHitResult.Type.PARRY_SUCCESS),"Reading the close route permits a second parry without damage")
				check(close_damage>0,"Staying close yields a real punish")
			else:
				check(row.player_hp==100,"Committed retreat remains a valid safe answer")
				check(row.punish_damage<close_damage,"Immediate jump and sustained retreat gives less punish than reading the close route")
	var output:=FileAccess.open(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("vine_escape.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(rows,"\t"))
	output.close()
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER VINE ESCAPE OBSERVATIONS")
