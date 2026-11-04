extends "../tests/support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerDuelBoss
var lan: LanPlayer
var move_counts: Dictionary = {}
var sequence: Array[String] = []
var outcomes: Dictionary = {}
var report: Array[Dictionary] = []
func press_k(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=KEY_K
	event.physical_keycode=KEY_K
	event.pressed=down
	Input.parse_input_event(event)
func on_move(id: StringName) -> void:
	move_counts[id]=int(move_counts.get(id,0))+1
	sequence.append(String(id))
func on_contact(_target: Node, result: int) -> void:
	outcomes[str(result)]=int(outcomes.get(str(result),0))+1
func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for phase in [1,2]:
		for policy in ["no_input","stationary_defense"]:
			for i in BossDevelopmentRoom.BOSS_CATALOG.size():
				var suffix := "/deer_duel_adapter.gd" if phase==1 else "/deer_root_duel_adapter.gd"
				if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with(suffix): room.select_boss(i)
			await process_frame
			room.set_combat_simulation(true)
			deer=room.adapter.boss
			lan=room.player
			var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
			assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
			assist.set_player_invincible(false)
			deer._rng.seed=20261104
			if phase==2: (deer as DeerRootDuelBoss).terrain.advance(2.5)
			lan.reset_after_map_fall(Vector2(600,deer.ground_y_at(600)))
			deer.position=Vector2(820,deer.ground_y_at(820))
			deer.move_started.connect(on_move)
			deer.attack_hitbox.hit_resolved.connect(on_contact)
			move_counts={}
			sequence=[]
			outcomes={}
			var recover_frames:=0
			var idle_frames:=0
			var damaging_frames:=0
			var summit_frames:=0
			var wave_contacts:=0
			var previous_wave: Dictionary={}
			var min_x:=lan.position.x
			var max_x:=lan.position.x
			var min_hp:=lan.combat_stats.health
			var action_start:=deer._time
			var last_press_serial:=-1
			var press_frame:=-10
			for f in 2700:
				if f==press_frame+1: press_k(false)
				if policy=="stationary_defense" and deer.opening<=0 and deer.move!=&"" and last_press_serial!=deer._duel_serial:
					var when: float={&"sweep":.48,&"rush":.60,&"leaf":.93,&"drop":999}.get(deer.move,999)
					if deer.age>=when:
						press_k(true)
						last_press_serial=deer._duel_serial
						press_frame=f
				await physics_frame
				if deer.opening>0: recover_frames+=1
				elif deer.move==&"": idle_frames+=1
				if deer.attack_hitbox.attack!=null: damaging_frames+=1
				if phase==2 and lan.position.y<430 and lan.position.x>140 and lan.position.x<1140: summit_frames+=1
				if phase==2:
					var wave: Node2D=(deer as DeerRootDuelBoss).contest_wave
					for pulse in wave.player_hits:
						var k: String="%d:%d" % [wave.cycle,pulse]
						if not previous_wave.has(k): previous_wave[k]=true; wave_contacts+=1
				min_x=minf(min_x,lan.position.x)
				max_x=maxf(max_x,lan.position.x)
				min_hp=mini(min_hp,lan.combat_stats.health)
			press_k(false)
			var sample := {"phase":phase,"policy":policy,"simulation_seconds":45,"action_seconds":deer._time-action_start,"moves":move_counts.duplicate(),"sequence":sequence.duplicate(),"contact_results":outcomes.duplicate(),"minimum_hp":min_hp,"end_hp":lan.combat_stats.health,"recovery_percent":recover_frames/27.0,"idle_percent":idle_frames/27.0,"live_attack_percent":damaging_frames/27.0,"on_summit_percent":summit_frames/27.0,"player_x_range":[min_x,max_x],"root_wave_contacts":wave_contacts}
			report.append(sample)
			print("SAMPLE "+JSON.stringify(sample))
	# Direct selection table tests whether the root wave changes choices at all.
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	var root_deer:=deer as DeerRootDuelBoss
	var table: Array[Dictionary]=[]
	for gap in [180,350,750]:
		for wave_age in [0.5,4.0,7.0]:
			var picks: Array[String]=[]
			for round_index in 3:
				deer.cancel_duel(false)
				deer.position=Vector2(220,415)
				lan.position=Vector2(220+gap,415)
				deer.wait_left=0
				root_deer.contest_round=round_index
				root_deer.contest_wave.clock=wave_age
				root_deer._contest_selection(1.0/60)
				picks.append(String(deer.move))
			table.append({"gap":gap,"wave_clock":wave_age,"choices":picks})
	print("SELECTION_TABLE "+JSON.stringify(table))
	var file:=FileAccess.open(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("boredom_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples":report,"selection_table":table},"\t"))
	file.close()
	expect_save_untouched()
	finish("DEER BOREDOM INVESTIGATION - MEASUREMENTS ONLY")
