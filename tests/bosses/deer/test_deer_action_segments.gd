extends SceneTree

var room
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale/60.0
		room.adapter.deer._physics_process(delta)
		room._physics_process(delta)
		room.adapter.deer.vfx._process(delta)

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene=room
	await process_frame; await process_frame
	room.set_physics_process(false);room.player.set_physics_process(false)
	var deer: DeerBoss=room.adapter.deer
	deer.set_physics_process(false);deer.vfx.set_process(false)
	var human_clips:=DeerActionLibrary.clips().keys().filter(func(n: String)->bool: return n.begins_with("human_")).size()
	check(DeerActionLibrary.clips().size()-human_clips==45 and human_clips==13,"All 45 deer and 13 human-form segment files are registered")
	check(not deer.animated_sprite.sprite_frames.has_animation(&"heavy") and not deer.animated_sprite.sprite_frames.has_animation(&"thrust"),"Runtime has no old full-sheet animation aliases")
	for name: String in DeerActionLibrary.clips():
		var clip:=DeerActionLibrary.clip(StringName(name))
		var family_ids: Array = DeerActionLibrary.data().families.keys()
		for family_index in family_ids.size():
			if DeerActionLibrary.family(StringName(family_ids[family_index])).values().has(name):
				room.select_segment_action(family_index)
				break
		var good:=true
		for i in int(clip.count):
			deer._show_clip(StringName(name),i)
			var atlas:=deer.animated_sprite.sprite_frames.get_frame_texture(name,i) as AtlasTexture
			good=good and atlas.atlas==DeerActionLibrary.texture(StringName(name)) and deer.core_offset().is_finite()
		check(good,"Independent texture and valid per-frame anchors: "+name)
		deer._show_clip(StringName(name), int(clip.count) / 2)
		await snapshot("clip_"+name)
	check(room.segment_row.visible and room.segment_picker.item_count==23,"Development room exposes all retained deer families, compound sub-actions and the five human-form families")
	for index in room.segment_picker.item_count:
		room.select_segment_action(index)
		var parts: Dictionary=room.adapter.segment_parts(index)
		check(room.segment_buttons[&"START"].disabled==not parts.has("START") and room.segment_buttons[&"END"].disabled==not parts.has("END"),"Missing source stages are disabled honestly")
		room.play_segment(&"ALL")
		tick(300)
		check(deer.segment_finished and String(deer.animated_sprite.animation)==String(deer.segment_sequence[-1]) and deer.attack_hitbox.attack==null,"Complete segment sequence ends in its final physical clip")
		await snapshot("family_%02d"%index)
	room.select_segment_action(DeerActionLibrary.data().families.keys().find("bind_push"))
	check(room.segment_buttons[&"END"].disabled,"Sustained horn push has no invented END clip")
	room.select_segment_action(DeerActionLibrary.data().families.keys().find("flick"))
	room.play_segment(&"ING");tick(8)
	check(deer.animated_sprite.animation==&"flick_ING","Full sweep and lift execution is actually selectable")
	await snapshot("flick_ING")
	room.play_segment(&"ALL");tick(165)
	check(deer.animated_sprite.animation==&"flick_END" and deer.segment_finished,"Flick now uses authored recovery rather than reversing its sweep")
	check(deer.start_segment_sequence(PackedStringArray(["thrust_ING","rear_gore_END"]),688),"Segment sequence can join independent stages without a full-sheet index")
	check(deer.animated_sprite.animation==&"thrust_ING","Chain begins directly in requested ING file")
	tick(40)
	check(deer.segment_finished and deer.animated_sprite.animation==&"rear_gore_END","Chain advances to requested independent END file")
	room.select_combo(2);room.play_action(2);tick(40)
	check(deer.animated_sprite.animation==&"bind_push_ING" and room.dummy.contacts.size()==1,"Real wind pressure uses the independent sustained execution clip")
	tick(66)
	check(deer.animated_sprite.animation==&"thrust_END","Horn push explicitly releases using a compatible authored END file")
	room.select_combo(0);room.play_action(0);tick(35)
	check(deer.animated_sprite.animation==&"light_ING" and deer.animated_sprite.frame==1 and room.dummy.contacts.size()==1,"Real hoof damage stays synchronized to local ING contact frame")
	await snapshot("light_contact")
	tick(30)
	check(deer.animated_sprite.animation==&"light_END","Real hoof action plays its full independent recovery")
	await snapshot("light_END")
	room.play_action(1);tick(85)
	check(deer.animated_sprite.animation==&"heavy_ING" and room.dummy.contacts.size()==1,"Real heavy landing enters its independent execution clip")
	await snapshot("heavy_contact")
	room.play_action(3);tick(75)
	check(deer.animated_sprite.animation==&"charge_run_ING","Real rush loops an independent run clip")
	while deer._segment==0:tick(1)
	check(deer.animated_sprite.animation==&"uppercut_START","Rush links into an independent uppercut startup")
	tick(10)
	check(deer.animated_sprite.animation==&"uppercut_ING" and room.dummy.contacts.size()==2,"Uppercut execution keeps its own second damage segment")
	await snapshot("uppercut_contact")
	room.reset_room();await process_frame;await process_frame
	check(room.adapter.deer.segment_index==-1 and room.adapter.deer.attack_hitbox.attack==null,"Reset clears pending physical segment chains")
	room.select_boss(1);await process_frame;await process_frame
	check(not room.segment_row.visible,"Other BOSS development controls remain independent")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH)==save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)==saved),"Segment inspection and real actions leave progress untouched")
	current_scene=null;room.free()
	print("ACTION SEGMENTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
