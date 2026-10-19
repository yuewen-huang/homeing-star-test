extends SceneTree

class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room
var master
var player: LanPlayer
var checks := 0
var failures := 0
var output := "D:/HomingStar/.artifacts/master-return-design/game"
var caption: Label
var outcomes: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)

func tick(delta := 1.0/120.0) -> void:
	master._process(delta)
	if room is BossDevelopmentRoom: room._physics_process(delta)

func until(time: float) -> void:
	while master.press_return != null and master.press_return.elapsed+0.000001 < time:
		tick(minf(1.0/120.0,time-master.press_return.elapsed))

func freeze() -> void:
	master = room.adapter.master if room is BossDevelopmentRoom else room.boss
	player = room.player
	master.set_process(false)
	master.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	player.set_physics_process(false)
	room.set_physics_process(false)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if caption != null:
		caption.text = "师傅一阶段 · 压步回锋【草稿】 / %s\n本体 %s F%02d · 新分叉风带 / 代码离线烘焙" % [label,master.animated_sprite.animation,master.animated_sprite.frame]
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func ready_guard() -> void:
	player.defense_state = LanPlayer.DefenseState.NONE
	player.defense_recoil_active = false
	player.hit_reaction_active = false
	player.play_idle()
	player.start_parry()
	player.animated_sprite.frame = 3
	player.on_player_animation_frame_changed()
	player.animated_sprite.pause()
	outcomes.clear()
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()

func settle_guard() -> void:
	ready_guard()
	await physics_frame
	await physics_frame
	await process_frame
	master.attack_hitbox._physics_process(0)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	var previous := root.get_node("SaveProgress")
	root.remove_child(previous)
	previous.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.select_combo(1)
	check(room.library_picker.get_item_text(0) == "咆哮强化","Same-sized phase libraries refresh their visible labels")
	room.select_combo(0)
	room.select_combo_library(3)
	room.reset_room()
	check(room.adapter.library_index == 3,"Reset keeps the displayed draft option and adapter selection in sync")
	room.play_action(4)
	freeze()
	check(master.press_return != null,"Development action library starts the review draft")
	check(master.press_return.track.size() == 32,"New frame track composes down-cut, two authored linking poses, and lifted recovery")
	for i in range(1,MasterPressReturn.KEYS.size()):
		var a: Array = MasterPressReturn.KEYS[i-1]
		var b: Array = MasterPressReturn.KEYS[i]
		var rate := float(b[1]-a[1])/float(b[0]-a[0])
		check(rate >= 4 and rate <= 40,"Fitted segment keeps readable playback %.2f fps" % rate)
	var start_x: float = master.position.x
	until(0.42)
	check(master.position.x < start_x and start_x-master.position.x <= MasterPressReturn.STEP_MAX,"A bounded forward step stops before the first slash")
	var settled_x: float = master.position.x
	await capture("dev_step")
	until(MasterPressReturn.FIRST_BEAT)
	check(master.animated_sprite.animation == &"attack_1_ING" and master.animated_sprite.frame == 1,"First beat uses the real down-cut contact pose")
	check(room.dummy.contacts.size() == 1,"First cut reaches the dummy once")
	var first: CombatAttackData = master.attack_hitbox.attack
	var smear: PixelSlash = master.press_return.smears[0]
	check(smear.shape == &"wind_ribbons" and not smear._clip.is_empty(),"Down-cut uses the new production-baked wind geometry")
	check(String(smear._clip.asset_path).begins_with("master_boss/press_return/"),"Draft does not sample a legacy texture or deer crescent")
	await capture("dev_first_beat")
	until(0.70)
	check(master.attack_hitbox.attack == first and room.dummy.contacts.size() == 1,"One cut keeps the same damage budget across several frames")
	until(0.78)
	await capture("dev_seam_before")
	until(0.96)
	await capture("dev_seam_after")
	check(master.animated_sprite.animation == &"attack_3_lift_START","First cut flows directly into a different rising motion")
	until(MasterPressReturn.SECOND_BEAT)
	check(master.animated_sprite.animation == &"attack_3_lift_ING" and master.animated_sprite.frame == 0,"Second contact is pinned to the rising cut")
	check(room.dummy.contacts.size() == 2,"Two-cut combo settles exactly twice on the dummy")
	check(master.attack_hitbox.attack != first,"Second cut has its own attack identity")
	var lift: PixelSlash = master.press_return.smears[1]
	check(lift.wind_profile == &"return_lift" and not lift._clip.is_empty(),"Rising cut has its own newly authored atlas clip")
	check(lift._clip.asset_path != smear._clip.asset_path,"Two opposing cuts do not reverse or rotate the same texture")
	check(is_equal_approx(master.position.x,settled_x),"No hidden slide or retargeting after the step")
	await capture("dev_second_beat")
	until(1.32)
	check(room.dummy.contacts.size() == 2,"Lift source F17/F18 do not accidentally double-hit")
	until(MasterPressReturn.DURATION)
	check(master.press_return == null and master.attack_hitbox.attack == null,"Full recovery clears combo and hitbox")
	await capture("dev_recovery")
	# Mirror, early interruption and resetting the specimen all clear wind.
	master.start_press_return(Vector2(1100,555))
	until(0.61)
	check(master.press_return.direction == 1 and master.press_return.smears[0].facing == 1,"Right-side target mirrors body and baked wind together")
	var frozen: float = master.press_return.elapsed
	var wind_age: float = master.press_return.smears[0].age
	master.start_parry_feedback()
	tick(0.03)
	check(is_equal_approx(master.press_return.elapsed,frozen),"Normal parry pause freezes poses, movement and painted wind")
	check(is_equal_approx(master.press_return.smears[0].age,wind_age),"Parry pause freezes the baked wind atlas frame")
	master._interrupt_for_special(0.1)
	check(master.press_return == null and master.attack_hitbox.attack == null,"Shared interrupt cancels the queued rising slash")
	room.play_action(4)
	freeze()
	until(0.61)
	room.reset_room()
	await process_frame
	freeze()
	check(master.press_return == null and master.get_node_or_null("PressReturnDraftWind") == null,"Reset removes draft wind with specimen")
	room.queue_free()
	await process_frame
	# Formal room: the same combo, real Lan guard, shared parry settlement.
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	freeze()
	master.position = Vector2(220,555)
	player.position = Vector2(88,555)
	master.start_press_return(player.position)
	master.attack_hitbox.hit_resolved.connect(func(target: Node,result: int) -> void:
		if target == player: outcomes.append(result))
	var layer := CanvasLayer.new()
	layer.layer = 80
	room.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(18,608)
	layer.add_child(caption)
	if OS.get_cmdline_user_args().has("--record"):
		for frame in 57:
			if frame > 0: tick(0.05)
			await capture("record_%03d" % frame)
		master.position = Vector2(220,555)
		player.position = Vector2(88,555)
		master.start_press_return(player.position)
	until(0.32)
	await capture("formal_windup")
	until(0.60)
	await capture("formal_first_cut")
	var health := player.combat_stats.health
	await settle_guard()
	check(outcomes.has(CombatHitResult.Type.PARRY_SUCCESS),"Real Lan manually parries the first new cut through overlap detection")
	check(get_nodes_in_group(CombatImpactEffect.GROUP).size() == 1,"First parry emits exactly one shared impact")
	check(master.parry_pause_remaining > 0 and master.press_return != null,"Ordinary parry pauses and preserves the next cut")
	await capture("formal_first_parry")
	until(MasterPressReturn.SECOND_BEAT)
	await capture("formal_second_cut")
	await settle_guard()
	check(outcomes.has(CombatHitResult.Type.PARRY_SUCCESS),"Real Lan manually parries the rising second cut")
	check(get_nodes_in_group(CombatImpactEffect.GROUP).size() == 1,"Second parry also emits one shared impact")
	check(player.combat_stats.health == health,"Two real manual parries preserve Lan health")
	await capture("formal_second_parry")
	until(MasterPressReturn.DURATION)
	await capture("formal_recovery")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists,"Save existence unchanged")
	if exists: check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved,"In-memory fixture leaves progression byte-identical")
	Engine.time_scale = 1.0
	print("MASTER PRESS RETURN: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
