extends SceneTree
const LIBRARY := preload("res://scripts/bosses/crystal_crab/crystal_crab_action_library.gd")
var room: BossDevelopmentRoom
var crab: CrystalCrabBoss
var checks := 0
var failures := 0
var index := -1
var save_before := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func advance(seconds: float) -> void:
	for i in ceili(seconds*60):
		crab._physics_process(1.0/60)
		room._physics_process(1.0/60)
func capture(label_: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label_+".png"))==OK,"Capture "+label_)
func run() -> void:
	save_before = FileAccess.get_file_as_string(SaveProgressService.SAVE_PATH)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	for i in room.BOSS_CATALOG.size():
		if room.BOSS_CATALOG[i].name=="盐场 · 晶蟹": index = i
	check(index>=0,"Crystal crab is registered in the existing shared room")
	room.boss_picker.item_selected.emit(index)
	await process_frame
	crab = room.adapter.boss as CrystalCrabBoss
	crab.set_physics_process(false)
	check(crab.manual_control and room.segment_picker.item_count==6,"Manual specimen exposes all six authored actions")
	check(not crab.is_in_group("damageable") and crab.get_node("Hurtbox").collision_layer==0,"Shared preview protection disables player damage against specimen")
	var at := crab.position
	advance(12)
	check(crab.action==&"idle" and crab.position==at and crab.attack_hitbox.attack==null,"Idle cycles through the complete source without autonomous attacks or drift")
	await capture("crystal_crab_idle")
	var frames := 0
	for action_index in LIBRARY.ACTIONS.size():
		var action: StringName = LIBRARY.ACTIONS[action_index]
		room.select_segment_action(action_index)
		for part in [&"START",&"ING",&"END"]:
			var clip := StringName(String(action)+"_"+String(part))
			var spec: Dictionary = LIBRARY.CLIPS[clip]
			frames += int(spec.count)
			check(spec.texture.get_size()==Vector2(int(spec.count)*256,256),"Independent native segment texture "+String(clip))
			check(not room.segment_buttons[part].disabled,"Shared segment button enables "+String(clip))
			room.segment_buttons[part].pressed.emit()
			check(crab.current_clip==clip and crab.animated_sprite.frame==0,"Segment starts from its own local frame zero "+String(clip))
			var authored_ground := 167
			if action==&"double_slam": authored_ground = 168
			elif action==&"burrow": authored_ground = 169 if part==&"START" else 180
			check(is_zero_approx((authored_ground+crab.animated_sprite.offset.y)*crab.animated_sprite.scale.y),"Authored guide aligns with room ground "+String(clip))
			check(is_equal_approx(LIBRARY.duration(clip),float(spec.count)*0.1),"Native Aseprite frame duration is preserved "+String(clip))
			advance(LIBRARY.duration(clip)+0.05)
			check(not crab.playing and crab.animated_sprite.frame==int(spec.count)-1,"Individual segment holds its authored final frame "+String(clip))
			check(crab.source_frame==int(spec.source_start)+int(spec.count)-1,"Source provenance is accurate "+String(clip))
		room.play_segment(&"ALL")
		var start := LIBRARY.duration(StringName(String(action)+"_START"))
		var middle := LIBRARY.duration(StringName(String(action)+"_ING"))
		var end := LIBRARY.duration(StringName(String(action)+"_END"))
		crab._physics_process(start+middle*0.5)
		check(crab.part==&"ING" and crab.action==action,"Complete action enters real ING "+String(action))
		crab._physics_process(middle*0.5+end*0.5)
		check(crab.part==&"END" and crab.action==action,"Complete action includes authored recovery "+String(action))
		crab._physics_process(end*0.5+0.01)
		check(crab.action==&"idle" and crab.playing,"Complete action recovers into full idle cycle "+String(action))
	check(frames==144,"All 144 source cells are covered once by 18 physical segments")
	for action_index in 5:
		if action_index == 4: room.select_combo_library(4)
		room.play_action(action_index)
		check(crab.action==[&"left_slam",&"right_slam",&"double_slam",&"walk",&"burrow"][action_index],"Existing action button triggers runtime action %d" % action_index)
		if action_index<3:
			var start := LIBRARY.duration(StringName(String(crab.action)+"_START"))
			advance(start-0.05)
			await capture("crystal_crab_%d_start" % action_index)
			advance(0.2)
			await capture("crystal_crab_%d_ing" % action_index)
			advance(LIBRARY.duration(StringName(String(crab.action)+"_ING")))
			await capture("crystal_crab_%d_end" % action_index)
	room.play_action(3)
	at = crab.position
	advance(1.3)
	check(crab.position.x<at.x-20 and crab.part==&"ING","Walk root movement follows its real ING phase")
	room.play_action(4)
	at = crab.position
	advance(0.8)
	check(crab.position==at,"Burrow remains at takeoff point throughout entry")
	await capture("crystal_crab_burrow_start")
	advance(0.6)
	check(crab.position.x<at.x-20 and crab.part==&"ING","Buried travel follows its real animation clock")
	await capture("crystal_crab_burrow_ing")
	advance(1.0)
	check(crab.part==&"END" and is_equal_approx(crab.position.x,room.dummy.position.x),"Emergence ends at the locked preview destination")
	await capture("crystal_crab_burrow_end")
	# Exercise the actual OptionButton and play button signals, not start_quake().
	room.dummy_x.value = 900
	for selected in CrystalCrabQuakeRhythm.ORDER.size():
		room.library_picker.item_selected.emit(selected)
		room.ultimate_button.pressed.emit()
		check(crab.rhythm != null and crab.rhythm.id == CrystalCrabQuakeRhythm.ORDER[selected],"UI selection and button 5 play the selected ground skill %d" % selected)
		var score_end := crab.rhythm.end_time
		var first_beat: float = crab.quake_beats[0].t
		advance(first_beat)
		var marker: Dictionary = CrystalCrabQuakeRhythm.CONTACTS[crab.quake_beats[0].anchor]
		var mean := Vector2.ZERO
		for point: Vector2 in marker.points: mean += point
		mean /= marker.points.size()
		var painted_contact := crab.animated_sprite.to_global(mean+crab.animated_sprite.offset)
		check(absf(painted_contact.x-crab.quake_beats[0].center.x)<0.01,"Ground centre matches rendered claw contact horizontally %d" % selected)
		check(is_equal_approx(crab.quake_beats[0].center.y,room.FLOOR_Y),"Ground art stays on the visible floor instead of inheriting painted claw depth %d" % selected)
		check(is_equal_approx(crab.attack_collision.global_position.x,painted_contact.x),"Damage footprint shares the painted contact X %d" % selected)
		check(not crab.quake_vfx.last_impact.is_empty(),"The ground beat selects a dedicated crab impact sound %d" % selected)
		await capture("crystal_crab_anchor_%d_active" % selected)
		advance(score_end-first_beat+0.15)
		check(not room.dummy.contacts.is_empty(),"Selected ground skill actually reaches the preview dummy %d" % selected)
		check(crab.quake_vfx.last_impact==[&"claw_b",&"double",&"echo",&"double",&"burrow",&"aftershock"][selected],"Every combo routes its closing beat to the authored impact sound %d" % selected)
		check(crab.quake_vfx.impact_voices.all(func(voice): return voice.bus==&"SFX" and (voice.stream==null or voice.stream.resource_path.begins_with("res://assets/sideview/audio/crystal_crab/"))),"Crab voices use the SFX bus and no landing placeholder %d" % selected)
	room.dummy_x.value = 688
	room.play_action(1)
	check(crab.direction == -1 and crab.animated_sprite.scale == Vector2(-2,2),"Body faces a target on its left")
	check(is_equal_approx(crab.quake_beats[0].center.x,crab.global_position.x-190),"Left-facing right-claw AOE is mirrored with the body")
	advance(0.70)
	await capture("crystal_crab_facing_left_active")
	room.dummy_x.value = 1020
	room.play_action(1)
	check(crab.direction == 1 and crab.animated_sprite.scale == Vector2(2,2),"Body faces a target on its right")
	check(is_equal_approx(crab.quake_beats[0].center.x,crab.global_position.x+190),"Right-facing right-claw AOE retains its authored offset")
	advance(0.70)
	await capture("crystal_crab_facing_right_active")
	room.play_action(2)
	advance(0.7)
	room.play_action(0)
	check(crab.action==&"left_slam" and crab.action_time==0 and crab.position==room.BOSS_START,"Replay safely replaces a running action and resets its origin")
	room.set_playback_speed(0)
	check(Engine.time_scale==0.25,"Crab uses the shared quarter-speed preview control")
	room.set_playback_speed(2)
	var old := crab
	room.reset_room()
	await process_frame
	crab = room.adapter.boss as CrystalCrabBoss
	crab.set_physics_process(false)
	check(crab!=old and crab.action==&"idle" and crab.position==room.BOSS_START,"Reset recreates a clean specimen")
	room.select_boss(3)
	await process_frame
	check(room.adapter.boss is FroggerBoss,"Switching back preserves existing BOSS adapters")
	check(get_nodes_in_group("damageable").is_empty(),"Switching leaves no attackable specimen behind")
	room.free()
	current_scene = null
	await process_frame
	check(FileAccess.get_file_as_string(SaveProgressService.SAVE_PATH)==save_before,"Preview leaves the real save byte-for-byte unchanged")
	check(Engine.time_scale==1.0,"Leaving restores playback speed")
	print("CRYSTAL CRAB DEVELOPMENT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
