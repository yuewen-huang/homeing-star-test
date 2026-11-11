extends "../../support/harness.gd"
## Real physics/timeline measurements, optionally captured with --write-movie.
var player: LanPlayer
var records: Dictionary = {}
var out := "res://../homeing-star-test/artifacts/lan_attack_rhythm_20261104"
var baseline := false

func step(n: int) -> void:
	for i in n: await physics_frame

func reset() -> void:
	Input.action_release(&"jump")
	Input.action_release(&"instant_dash")
	player.reset_after_map_fall(Vector2(600,520))
	player.combat_stats.stamina=player.combat_stats.max_stamina
	await step(4)

func measure(action: StringName, queued: bool) -> Dictionary:
	await reset()
	player.call(action,1.0)
	var state := player.attack_state
	var active: Array[int] = []
	var closed := -1
	var end := -1
	for tick in 90:
		if queued and tick==2: player.update_combat_input_buffers(0.0,true,false,false)
		await step(1)
		if player.attack_state!=state:
			end=tick
			break
		if is_instance_valid(player.timeline_attack_effect) and player.timeline_attack_effect.hitbox.monitoring:
			active.append(tick)
		if closed<0 and player.attack_effect_spawned and not is_instance_valid(player.timeline_attack_effect): closed=tick
	return {"active_ticks":active,"closed_tick":closed,"end_tick":end,"next_state":player.attack_state}

func run() -> void:
	baseline="--baseline" in OS.get_cmdline_user_args()
	use_memory_progress()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var world:=Node2D.new()
	root.add_child(world)
	current_scene=world
	RenderingServer.set_default_clear_color(Color("17252e"))
	var floor_art:=Polygon2D.new()
	floor_art.polygon=PackedVector2Array([Vector2(0,520),Vector2(1280,520),Vector2(1280,720),Vector2(0,720)])
	floor_art.color=Color("354950")
	world.add_child(floor_art)
	player=load("res://scenes/player/lan/lan_player.tscn").instantiate()
	player.position=Vector2(600,520)
	player.fallback_ground_y=520
	player.world_min_x=0
	player.world_max_x=1280
	world.add_child(player)
	await step(3)
	for action in [&"start_attack_1x",&"start_attack_2x_1",&"start_attack_2x_2",&"start_attack_2x"]:
		for queued in [false,true]:
			var key: String=str(action)+("_queued" if queued else "_single")
			records[key]=await measure(action,queued)
			print(key,": ",records[key])
			await step(25)
	var file:=FileAccess.open(out.path_join("before.json" if baseline else "after.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t"))
	file.close()
	if not baseline:
		# Captured from the pre-refinement production timeline at fixed 60 Hz.
		var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../homeing-star-test/tests/player/lan/fixtures/attack_rhythm_baseline.json"))
		for key: String in records:
			check(PackedInt32Array(records[key].active_ticks)==PackedInt32Array(prior[key].active_ticks),"%s preserves every active damage tick" % key)
			# The old snapshot stores enum ordinals; the finisher's ordinal has since changed.
			var destination: int = LanPlayer.AttackState.ATTACK_3X \
				if key == "start_attack_2x_queued" else int(prior[key].next_state)
			check(records[key].next_state==destination or key=="start_attack_1x_queued","%s preserves the combo destination" % key)
		for action in ["start_attack_1x","start_attack_2x_2","start_attack_2x"]:
			var key: String=action+"_queued"
			check(records[key].end_tick<prior[key].end_tick,"%s chains earlier after the live effect" % action)
			check(records[key].end_tick<=records[action+"_single"].closed_tick+1,"%s chains within one tick of effect closure" % action)
		check(records.start_attack_1x_single.end_tick==prior.start_attack_1x_single.end_tick,"First single attack timing stays intact")
		check(records.start_attack_2x_single.end_tick<prior.start_attack_2x_single.end_tick,"Slow second attack recovers sooner even without a follow-up")
		check(records.start_attack_2x_1_single.end_tick==prior.start_attack_2x_1_single.end_tick,"Already short alternate stays intact")
		# Defensive requests beat a queued combo on the same recovery boundary.
		for defense in ["jump","dash","dodge","parry"]:
			await reset()
			player.start_attack_1x(1.0)
			for i in 50:
				await step(1)
				if player.can_cancel_normal_attack_recovery(): break
			player.update_combat_input_buffers(0.0,true,defense=="dodge",defense=="parry")
			if defense=="jump": Input.action_press(&"jump")
			if defense=="dash": Input.action_press(&"instant_dash")
			await step(2)
			var ok:=false
			match defense:
				"jump": ok=player.velocity.y<0 and player.attack_state==LanPlayer.AttackState.NONE
				"dash": ok=player.attack_state==LanPlayer.AttackState.INSTANT_DASH
				"dodge": ok=player.ground_action_state==LanPlayer.GroundActionState.BACK_DODGE
				"parry": ok=player.defense_state!=LanPlayer.DefenseState.NONE
			check(ok and not player.attack_queued,"%s wins over an attack queued on the same frame" % defense)
	await reset()
	check(player.get_node("StateTrace").report_count==0,"No animation-owner contradiction during the attack sequence")
	expect_save_untouched()
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream=null
	world.queue_free()
	await wait_frames(8)
	finish("LAN ATTACK RHYTHM")
