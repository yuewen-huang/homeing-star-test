extends SceneTree
var room
var deer: DeerBoss
var output := ""
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("OK " if value else "FAIL ",label)
func tick(count: int, speed := 1.0) -> void:
	for i in count:
		deer._physics_process(speed/60)
		room._physics_process(speed/60)
		deer.vfx._process(speed/60)
func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name+".png")) == OK)
func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	var existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	deer = room.adapter.deer
	deer.set_physics_process(false); deer.vfx.set_process(false)
	room.player.set_physics_process(false); room.set_physics_process(false)
	room.play_action(0); tick(8)
	check(deer.animated_sprite.frame == 1 and is_equal_approx(deer.animated_sprite.position.y,-124*1.4+1.4),"Artist light F01 shifts down exactly one art pixel")
	await snapshot("01_light_alignment")
	tick(42)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 12,"Real light still deals one 12-damage contact")
	check(deer.vfx._light_impacts.is_empty() and not deer.vfx._painted.is_empty(),"Light uses supplied artwork without procedural overlay")
	check(deer.vfx._painted[0].back.visible,"User's light back layer reaches its authored visible frame")
	await snapshot("02_light_painted")
	room.play_action(1); tick(104)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 20,"Heavy still deals one 20-damage contact")
	check(deer.vfx.heavy_dust_bursts().is_empty() and not deer.vfx._painted.is_empty(),"Heavy replaces generated dust with the user painting")
	await snapshot("03_heavy_painted")
	room.play_action(3); tick(8)
	check(deer.animated_sprite.frame == 1 and is_equal_approx(deer.animated_sprite.position.y,-124*1.4-1.4),"Artist charge F01 shifts up exactly one art pixel")
	await snapshot("04_charge_alignment")
	tick(67)
	check(is_instance_valid(deer.vfx._painted_rush) and deer.vfx._painted_rush.back.visible,"Regular rush follows the deer with the supplied back-layer cycle")
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == CombatTuning.BOSS_PLAYER_GOLD_DAMAGE,"Rush contact uses the shared gold damage")
	await snapshot("05_rush_painted")
	while deer._segment == 0: tick(1)
	tick(19)
	check(room.dummy.contacts.size() == 2 and room.dummy.contacts[1].damage == CombatTuning.BOSS_PLAYER_GOLD_DAMAGE,"Uppercut keeps a separate gold-damage contact")
	check(is_instance_valid(deer.vfx._painted_uppercut) and deer.vfx._painted_uppercut.front.visible,"User's blue uppercut is shown in front of the body")
	check(not is_instance_valid(deer.vfx._painted_rush),"Uppercut closes the looping rush layer")
	await snapshot("06_uppercut_painted")
	tick(160)
	check(deer.vfx._painted.is_empty() and deer.state == DeerBoss.State.IDLE,"Painted effects finish with the actual action")
	room.dummy_x.value = 1000; room.play_action(3); tick(100)
	check(deer.direction > 0 and room.dummy.contacts.size() == 2,"Mirrored action still has exactly two contacts")
	check(is_instance_valid(deer.vfx._painted_uppercut) and deer.vfx._painted_uppercut.scale.x == -1,"Painted artwork mirrors around the original foot anchor")
	await snapshot("07_mirrored_uppercut")
	room.play_action(0); tick(42)
	var effect: DeerPaintedEffect = deer.vfx._painted[0]
	var previous := effect.elapsed
	tick(12,0.25)
	check(is_equal_approx(effect.elapsed-previous,0.05),"Quarter-speed advances painted time by exactly 50 ms over 12 ticks")
	deer.enter_stagger(2)
	check(deer.vfx._painted.is_empty(),"Interruption clears both painted depth layers")
	room.play_action(4)
	while deer.state != DeerBoss.State.HUNT_CHARGE: tick(1)
	tick(2)
	check(is_instance_valid(deer.vfx._painted_rush) and deer.vfx._painted_rush.kind == "mist_dash", "Mist ultimate uses its finished dedicated charge painting")
	while deer.state == DeerBoss.State.HUNT_CHARGE: tick(1)
	check(not is_instance_valid(deer.vfx._painted_rush),"Next hunt warning does not retain rush art across the teleport")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == existed and (not existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved),"Saved progress and inventory unchanged")
	current_scene = null; room.free()
	print("PAINTED DEER: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
