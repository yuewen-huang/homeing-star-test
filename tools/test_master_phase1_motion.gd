extends SceneTree

var room
var master
var checks := 0
var failures := 0
var output := "D:/HomingStar/.artifacts/master-motion-20261019/game"
var caption: Label

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)

func freeze() -> void:
	master = room.adapter.master if room is BossDevelopmentRoom else room.boss
	master.set_process(false)
	master.set_physics_process(false)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)

func until(time: float) -> void:
	while master.phase_1_motion.elapsed+0.000001 < time:
		var before: float = master.phase_1_motion.elapsed
		master._process(minf(1.0/120.0,time-before))
		if room is BossDevelopmentRoom: room._physics_process(0)

func start(index: int) -> void:
	room.select_combo_library(4+index)
	room.play_action(4)
	freeze()

func add_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	room.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(18,566)
	layer.add_child(caption)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var motion: MasterPhase1Motion = master.phase_1_motion
	caption.text = "师傅 · 动作编排【无伤害／无新增特效】 · %s\n%s · 源 F%02d · %.2fs" % [motion.route,motion.stage(),motion.source_frame,motion.elapsed]
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	add_caption()
	check(room.segment_picker.item_count == 19,"Two missing strike submoves are available beside the eleven source actions")
	check(room.adapter.combo_library_names().size() == 10,"Six body routes coexist with legacy and effect-draft options")
	for index in MasterPhase1Motion.IDS.size():
		start(index)
		var motion: MasterPhase1Motion = master.phase_1_motion
		check(motion != null and motion.route == MasterPhase1Motion.IDS[index],"Library starts "+String(MasterPhase1Motion.IDS[index]))
		var physical := true
		for pose: Array in motion.track:
			var texture := master.animated_sprite.sprite_frames.get_frame_texture(pose[1],pose[2]) as AtlasTexture
			physical = physical and texture.atlas.resource_path.ends_with("/actions/"+String(pose[1])+".png")
		check(physical,"Every pose comes from its physical segment PNG")
		var keys: Array = motion.data["keys"]
		var readable := true
		for i in range(1,keys.size()):
			var speed := float(keys[i][1]-keys[i-1][1])/float(keys[i][0]-keys[i-1][0])
			readable = readable and (is_zero_approx(speed) or (speed >= 4 and speed <= 40))
		check(readable,"Body playback stays forward at 4–40fps; explicit pauses do not reverse frames")
		if OS.get_cmdline_user_args().has("--record"):
			var count := ceili(motion.duration()*20)+1
			for i in count:
				until(minf(float(i)/20,motion.duration()))
				await capture("%s_%03d" % [motion.route,i])
		else:
			until(motion.duration())
		check(motion.finished and master.animated_sprite.frame == motion.track[-1][2],"Full authored recovery ends held, without an idle-frame jump")
		var end_frame: int = master.animated_sprite.frame
		master._process(0.5)
		check(master.animated_sprite.frame == end_frame,"Completed route never loops or restarts")
		check(master.attack_hitbox.attack == null and room.dummy.contacts.is_empty(),"Body review does not masquerade as completed combat or launch invisible attacks")
		check(not master.wind_effect.visible,"Old effects are not hard-reused for unapproved new motion")
	# Verify the cross-source seam and deliberate delayed finisher in actual frames.
	start(3)
	until(0.949)
	check(master.phase_1_motion.source_frame == 12 and master.animated_sprite.animation == &"attack_3_spin_ING","Spin retains its last low pose before the seam")
	await capture("spin_seam_before")
	until(0.95)
	check(master.phase_1_motion.source_frame == 13 and master.animated_sprite.animation == &"attack_2_return_START","Low return starts at F13, skipping the upright F11/F12 reset")
	await capture("spin_seam_after")
	until(1.43)
	var held: int = master.phase_1_motion.current_index
	until(1.73)
	check(master.phase_1_motion.current_index == held and master.phase_1_motion.source_frame == 19,"Delayed finisher holds a real prepared pose for 0.32 action seconds")
	await capture("spin_finisher_hold")
	until(1.86)
	check(master.phase_1_motion.source_frame == 20,"Finisher releases into the authored striking pose")
	await capture("spin_finisher_release")
	# Teleport locks on disappearance, not after the target has already dodged.
	start(4)
	var origin_x: float = master.position.x
	until(0.36)
	check(not master.animated_sprite.visible and is_equal_approx(master.position.x,origin_x),"Vanish is visible as a body disappearance before repositioning")
	var blink_x: float = master.phase_1_motion.landing_x
	room.dummy_x.value = 1100
	until(0.43)
	check(master.animated_sprite.visible and is_equal_approx(master.position.x,blink_x),"Reappearance uses the previously locked destination")
	until(1.92)
	check(master.animated_sprite.flip_h == (master.phase_1_motion.direction > 0),"Oppositely authored special retains its own facing rule")
	await capture("blink_special")
	until(2.37)
	check(master.animated_sprite.animation == &"attack_3_lift_END","Raised special returns through an authored lowering motion")
	await capture("blink_recovery_bridge")
	# Air motion: wait through spin, lock only when diving, then stop tracking.
	room.dummy_x.value = 688
	start(5)
	until(0.80)
	var airborne: Vector2 = master.position
	check(airborne.y < 555 and not master.phase_1_motion.destination_locked,"Airborne spin has root height but does not prematurely lock the plunge")
	await capture("air_spin")
	room.dummy_x.value = 580
	until(MasterPhase1Motion.AIR_PLUNGE_BEGIN)
	var plunge_x: float = master.phase_1_motion.landing_x
	check(master.phase_1_motion.locked_target.x == 580,"Plunge locks the target when the raised-sword commitment begins")
	await capture("air_plunge_start")
	room.dummy_x.value = 1100
	until(MasterPhase1Motion.AIR_LAND)
	check(is_equal_approx(master.position.x,plunge_x) and is_equal_approx(master.position.y,555),"Fast diagonal plunge reaches its fixed destination in 0.13 action seconds")
	check(master.position.x < airborne.x and master.phase_1_motion.source_frame == 17,"Forward/down translation accompanies the real landing pose")
	await capture("air_land")
	# Slow motion, cancellation and reset share the real master's ownership path.
	start(5)
	until(0.8)
	master._on_target_dodge_evaded_attack(master,1.0)
	var before: float = master.phase_1_motion.elapsed
	master._process(0.1)
	check(is_equal_approx(master.phase_1_motion.elapsed-before,0.01),"Global dodge time scales the full motion clock and root path")
	master._start_attack(&"attack_1")
	check(master.phase_1_motion == null and is_equal_approx(master.position.y,555),"Cancelling an airborne motion cannot leave the next attack floating")
	room.dummy_x.value = 1100
	start(5)
	until(0.8)
	check(master.phase_1_motion.direction == 1 and not master.animated_sprite.flip_h,"Right-facing air motion mirrors the body and root trajectory together")
	check(master.position.x >= master.world_min_x and master.position.x <= master.world_max_x,"Movement stays within the real room bounds")
	room.reset_room()
	await process_frame
	freeze()
	check(master.phase_1_motion == null and master.position == BossDevelopmentRoom.BOSS_START,"Reset clears motion and restores the specimen origin")
	room.select_combo(1)
	check(not room.adapter.master.start_phase_1_motion(&"air_plunge",Vector2.ZERO),"Phase-two cannot accidentally start a phase-one body route")
	room.queue_free()
	await process_frame
	# Also render the same controller on the production room's master.
	room = load("res://scenes/sideview/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	freeze()
	add_caption()
	master.position = Vector2(220,555)
	room.player.position = Vector2(88,555)
	master.start_phase_1_motion(&"spin_delayed",room.player.position)
	check(root.get_visible_rect().has_point(master.get_global_transform_with_canvas().origin),"Production render keeps the real master inside the camera")
	until(0.50)
	await capture("formal_spin_first_cut")
	until(0.95)
	await capture("formal_spin_seam")
	until(1.60)
	await capture("formal_spin_hold")
	until(1.86)
	await capture("formal_spin_finisher")
	until(2.31)
	await capture("formal_spin_recovery")
	check(master.attack_hitbox.attack == null,"Production-room body review remains explicitly unarmed")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists,"Motion review preserves save existence")
	if exists: check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved,"Motion review leaves player progression byte-identical")
	Engine.time_scale = 1.0
	print("MASTER PHASE ONE MOTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
