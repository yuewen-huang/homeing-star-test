extends "../tests/support/harness.gd"
## Real-input observations; these policies are not a player-skill model.
var room: BossDevelopmentRoom
var deer: Node2D
var lan: LanPlayer
var elapsed := 0.0
var last_health := 0
var broken_damage := 0
var normal_damage := 0
var deaths := 0
var sequence: Array[Dictionary] = []
var breaks: Array[Dictionary] = []
var samples: Array[Dictionary] = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_J,KEY_I,KEY_O,KEY_E]: key(code,false)
	for action in [&"ui_left",&"ui_right",&"special_attack"]: Input.action_release(action)

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	var hunt := OS.get_cmdline_user_args().has("--hunt")
	var pursuit := OS.get_cmdline_user_args().has("--pursuit")
	for policy in (["no_input","chase_j","chase_j_i_e"] if hunt or pursuit else ["no_input","chase_j","chase_j_i_e","repeat_o"]):
		room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
		root.add_child(room)
		current_scene = room
		await wait_frames(2)
		for i in BossDevelopmentRoom.BOSS_CATALOG.size():
			if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_pursuit_adapter.gd" if pursuit else "deer_vine_duel_adapter.gd"): room.select_boss(i)
		await process_frame
		room.set_combat_simulation(true)
		deer = room.adapter.boss
		if pursuit: deer._rng.seed=31534
		if hunt: deer.pressure.selected=3
		lan = room.player
		lan.reset_after_map_fall(Vector2(660,555))
		deer.position = Vector2(820,555)
		elapsed = 0
		sequence = []
		breaks = []
		deaths = 0
		broken_damage = 0
		normal_damage = 0
		last_health = deer.combat_stats.health
		deer.move_started.connect(func(id): sequence.append({"time":elapsed,"move":String(id)}))
		deer.combat_stats.poise_depleted.connect(func(): breaks.append({"time":elapsed,"health":deer.combat_stats.health,"completed":deer.pressure.completed}))
		deer.combat_stats.health_changed.connect(func(hp,_maximum):
			if hp<last_health:
				if deer.poise_broken: broken_damage += last_health-hp
				else: normal_damage += last_health-hp
			last_health=hp)
		lan.combat_stats.health_depleted.connect(func(): deaths+=1)
		var recovery := 0
		var minimum_hp := 100
		var ultimate_frames := 0
		for frame in 3600:
			elapsed=frame/60.0
			release()
			if policy=="repeat_o":
				if not lan.ultimate_active and frame%8==0: key(KEY_O,true)
			elif policy!="no_input":
				var gap: float = deer.position.x-lan.position.x
				if absf(gap)>105: Input.action_press(&"ui_right" if gap>0 else &"ui_left")
				if absf(gap)<210:
					lan.facing_direction=signf(gap) if gap!=0 else 1
					if policy=="chase_j_i_e" and frame%24==0:
						key(KEY_I,true)
						Input.action_press(&"special_attack")
					elif frame%10==0: key(KEY_J,true)
					if policy=="chase_j_i_e" and frame%10==0: key(KEY_E,true)
			await physics_frame
			if deer.opening>0: recovery+=1
			if lan.ultimate_active: ultimate_frames+=1
			minimum_hp=mini(minimum_hp,lan.combat_stats.health)
			if deer._stopped or deaths>0 or lan.input_frozen: break
		var frames_run: float = elapsed*60+1
		var row := {"policy":policy,"seconds":frames_run/60,"boss_health":deer.combat_stats.health,"boss_dead":deer._stopped,"player_min_hp":minimum_hp,"player_deaths":deaths,"completed_phrases":deer.pressure.completed,"normal_damage":normal_damage,"break_damage":broken_damage,"breaks":breaks.duplicate(true),"recovery_percent":recovery/frames_run*100,"ultimate_percent":ultimate_frames/frames_run*100,"sequence":sequence.duplicate(true)}
		samples.append(row)
		print("VINE_PRESSURE "+JSON.stringify(row))
		release()
		current_scene=null
		room.free()
		await process_frame
	var file := FileAccess.open(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("vine_pressure_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"\t"))
	file.close()
	expect_save_untouched()
	finish("VINE PRESSURE OBSERVATIONS")
