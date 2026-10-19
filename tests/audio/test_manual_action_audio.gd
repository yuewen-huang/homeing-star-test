extends SceneTree
var room
var player: LanPlayer
var deer: DeerBoss
var failures := 0
var checks := 0
var recording: AudioEffectRecord
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	if not OS.get_cmdline_user_args().is_empty():
		recording = AudioEffectRecord.new(); recording.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(sfx_bus,recording); recording.set_recording_active(true)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await frames(3)
	player = room.player; deer = room.adapter.deer
	var movement := player.movement_audio
	check(movement.forest_ground,"Dedicated BOSS room uses the forest movement sounds")
	var voices := [movement.jump_audio,movement.ground_audio,deer.vfx.warning_audio,deer.vfx.impact_audio,deer.vfx.call_audio,deer.vfx.run_audio]
	var sfx_only := true
	for voice in voices: sfx_only = sfx_only and voice.bus == &"SFX"
	check(sfx_only,"Every action sound follows the existing SFX volume setting")
	var health := player.combat_stats.health
	Input.action_press(&"jump"); await frames(2)
	check(player.air_state == LanPlayer.AirState.RISING and movement.jump_audio.stream == LanMovementAudio.JUMP and movement.jump_audio.playing,"Ordinary jump plays the new takeoff sound")
	Input.action_release(&"jump"); await frames(5)
	Input.action_press(&"jump"); await frames(2)
	check(player.double_jump_used and movement.jump_audio.stream == LanMovementAudio.DOUBLE_JUMP and movement.jump_audio.playing,"Actual second jump uses its own authored sound")
	Input.action_release(&"jump")
	var landed := false
	for i in 150:
		await physics_frame
		if movement.ground_audio.playing and movement.ground_audio.stream == LanMovementAudio.LAND:
			landed = true; break
	check(landed,"Ground contact plays the forest landing sound")
	await frames(35); player.reset_after_map_fall(Vector2(380,555))
	Input.action_press("ui_right"); await frames(2); Input.action_release("ui_right"); await frames(2); Input.action_press("ui_right")
	var steps := {}
	for i in 65:
		await physics_frame
		if movement.ground_audio.playing and movement.ground_audio.stream in LanMovementAudio.STEPS:
			steps[movement.ground_audio.stream] = true
	check(player.is_run_state() and steps.size() == 2,"Actual double-tap running alternates both footfalls at animation contacts")
	Input.action_release("ui_right"); await frames(3)
	check(not movement.ground_audio.playing,"Run stop immediately clears unfinished footsteps")
	player.reset_after_map_fall(Vector2(380,555))
	Input.action_press("ui_right"); await frames(30)
	check(movement.ground_audio.stream in LanMovementAudio.WALK_STEPS,"Walking uses the two dedicated walk sounds rather than running audio")
	Input.action_release("ui_right"); await frames(3)
	player.reset_after_map_fall(Vector2(380,555))
	Input.action_press("ui_right"); await frames(2); Input.action_release("ui_right"); await frames(2); Input.action_press("ui_right"); await frames(22)
	Input.action_press(&"jump"); await frames(2)
	check(not movement.ground_audio.playing,"Takeoff immediately stops the previous ground footfall")
	Input.action_release(&"jump"); Input.action_release("ui_right"); player.reset_after_map_fall(Vector2(380,555))
	player.start_jump(); player.input_frozen = true; await frames(2)
	check(not movement.ground_audio.playing and movement.jump_audio.stream_paused,"Input freeze stops footsteps and pauses any jump sound")
	player.input_frozen = false; await frames(2)
	check(not movement.jump_audio.stream_paused,"Jump audio unpauses with the player")
	# The same player in a non-forest room keeps takeoff sounds but excludes forest ground.
	var stone := Node2D.new(); stone.set_meta(&"footstep_surface","stone"); room.add_child(stone)
	var other := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	other.world_min_x = 32; other.world_max_x = 1248; other.position = Vector2(200,555)
	other.save_progress = player.save_progress; other.save_progress_resolved = true
	stone.add_child(other); other.set_physics_process(false); other.movement_audio.set_physics_process(false)
	other.start_jump(); other.movement_audio.play_landing()
	check(not other.movement_audio.forest_ground and other.movement_audio.jump_audio.playing and not other.movement_audio.ground_audio.playing,"Stone surface keeps jumps and excludes forest landing/steps")
	stone.free()
	room.play_action(1); await frames(2)
	check(not deer.vfx.call_audio.playing,"Ordinary heavy attack never triggers a deer call")
	room.play_action(2); await frames(125)
	check(not deer.vfx.call_audio.playing,"Heavy combo contact stays silent instead of calling on every stomp")
	room.play_action(4); await frames(2)
	check(deer.vfx.call_audio.playing and deer.vfx.call_audio.stream == DeerBossVFX.CALL_FAR,"Mist-ultimate opening starts the distant call")
	check(is_zero_approx(deer.vfx.call_audio.volume_db) and deer.vfx._sounds["howl"] == DeerBossVFX.CALL_FAR,"Distant call uses the requested zero-dB mix without using the near recording")
	await frames(75)
	check(deer.state == DeerBoss.State.HUNT_WARNING and deer.vfx.warning_audio.stream == DeerBossVFX.CHARGE_WARNING and deer.vfx.call_audio.playing,"Rush warning uses the recording without cutting off the separate deer call")
	room.play_action(3); await frames(2)
	check(deer.vfx.warning_audio.playing and deer.vfx.warning_audio.stream == DeerBossVFX.CHARGE_WARNING and not deer.vfx.run_audio.playing,"Normal rush windup warns before any running audio")
	await frames(62)
	check(deer.vfx.run_audio.playing and deer.vfx.run_audio.stream == DeerBossVFX.DEER_RUN and deer.vfx.run_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,"Real charge movement starts the looped authored deer footsteps")
	deer.red_parry_hold = true; await frames(2)
	check(deer.vfx.run_audio.stream_paused,"Combat hold pauses the deer sound tracks")
	var held_position := deer.vfx.run_audio.get_playback_position()
	await frames(4)
	check(absf(deer.vfx.run_audio.get_playback_position()-held_position) < 0.04,"Paused deer footsteps keep their playback cursor")
	deer.red_parry_hold = false; await frames(2)
	check(not deer.vfx.run_audio.stream_paused,"Resuming combat also resumes the deer sound tracks")
	Engine.time_scale = 0.25; deer.vfx._process(0)
	check(is_equal_approx(deer.vfx.run_audio.pitch_scale,0.25),"Quarter-speed playback slows audio with the combat action")
	Engine.time_scale = 1.0
	await frames(90)
	check(not deer.vfx.run_audio.playing,"Charge movement ends its running sound before uppercut/recovery")
	room.select_combo(1); room.play_action(4); await frames(2)
	check(deer.vfx.call_audio.stream == DeerBossVFX.CALL_FAR and deer.vfx.call_audio.playing and not deer.vfx.run_audio.playing,"Root ultimate calls without inventing a root-phase charge sound")
	room.play_action(1); await frames(2)
	deer.enter_stagger(1)
	check(not deer.vfx.call_audio.playing and not deer.vfx.run_audio.playing and not deer.vfx.warning_audio.playing,"Stagger cancels unfinished action audio")
	room.select_boss(1); await frames(3)
	check(not is_instance_valid(deer),"Changing BOSS removes all old deer audio nodes")
	check(player.combat_stats.health == health,"Audio preview leaves player health unchanged")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists and (not exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved),"Audio preview never writes progress/inventory")
	if recording != null:
		recording.set_recording_active(false)
		var captured := recording.get_recording(); captured.save_to_wav(OS.get_cmdline_user_args()[0])
		AudioServer.remove_bus_effect(sfx_bus,AudioServer.get_bus_effect_count(sfx_bus)-1)
		print("CAPTURED ",captured.get_length()," seconds of actual SFX output")
	current_scene = null; room.free()
	print("MANUAL ACTION AUDIO: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
