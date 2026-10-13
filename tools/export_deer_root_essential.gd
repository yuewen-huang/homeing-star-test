extends "export_deer_root_reference.gd"
# Small drawing units: keep distinct root VFX, remove duplicated volleys/poses.
var original: Dictionary

func export_unit(id: String, name: String, heights: Array, warning: float, times: Array, stages: Array, reference_kind: String, decoy := false) -> void:
	clear_effects()
	canvas = Vector2i(512,384); anchor = Vector2(256,332); viewport.size = canvas
	deer.position = Vector2(820,555); deer.direction = -1
	var xs: Array = []; var warns: Array = []; var eruptions: Array = []
	var spacing := 48 if heights.size() == 5 else (44 if heights[0] == 112 else 32)
	for i in heights.size():
		xs.append(620 + (i - (heights.size()-1)*0.5)*spacing)
		warns.append(0.0); eruptions.append(warning)
	add_roots(xs,warns,eruptions,heights)
	if decoy:
		var player_sprite: AnimatedSprite2D = room.player.animated_sprite
		ghost.texture = player_sprite.sprite_frames.get_frame_texture(player_sprite.animation,player_sprite.frame)
		ghost.position = Vector2(620,555) + player_sprite.position
		ghost.scale = player_sprite.scale; ghost.offset = player_sprite.offset
		ghost.modulate = Color(0.65,0.91,1,0.75)
		ghost.show()
	var folder := output.path_join("raw").path_join(id)
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	var heavy_ref: Dictionary = original.clips.filter(func(c: Dictionary) -> bool: return c.id == "heavy_wave")[0]
	for i in times.size():
		elapsed = times[i]
		for node in roots: node._time = elapsed; node.queue_redraw()
		if reference_kind == "heavy":
			var ref: Dictionary = heavy_ref.frames[mini(heavy_ref.frames.size()-1, int((1.44+elapsed)*20))]
			deer._art_context = "heavy_stomp"
			show_archived_pose(String(ref.animation),int(ref.body_frame),1.44+elapsed)
		else:
			deer._art_context = ""
			deer._show_clip(&"roar_ING",4 if reference_kind == "tracking" else 7)
		var duration := roundi((float(times[i+1])-elapsed)*1000) if i+1 < times.size() else 50
		# Retain one full-height cel, with no long wait in the drawing preview.
		if duration > 300: duration = 50
		frames.append({"index":i,"time_ms":0,"source_time_ms":roundi(elapsed*1000),"duration_ms":duration,"stage":stages[i],"animation":String(deer.animated_sprite.animation),"body_frame":deer.animated_sprite.frame,"world_position":[deer.position.x,deer.position.y],"direction":-1,"concept_only":true})
		await capture(folder,i)
	clips.append({"id":id,"name":name,"folder":folder,"canvas":[512,384],"anchor":[256,332],"effect_origin":[roundi(256-200/1.4),332],"frames":frames})
	print("SHORT ROOT UNIT ",id," ",frames.size()," keyframes")

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	original = JSON.parse_string(FileAccess.get_file_as_string("E:/HomingStar/Art/deer-root-concepts-20261010/capture_manifest.json"))
	DirAccess.make_dir_recursive_absolute(output)
	var existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	deer = room.adapter.boss as DeerBoss
	deer.set_physics_process(false); deer.vfx.set_process(false)
	room.player.set_physics_process(false); room.set_physics_process(false); room.set_process(false); room.hide()
	viewport = SubViewport.new(); viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	body = Sprite2D.new(); body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; viewport.add_child(body)
	ghost = Sprite2D.new(); ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; viewport.add_child(ghost)
	flow = ReturnFlow.new(); viewport.add_child(flow)
	await export_unit("heavy_single","02_根重击_单根破土",[36],0.42,[0.0,0.14,0.28,0.42,0.47,0.51,1.06,1.11,1.16,1.21,1.3,1.5,1.75],["裂纹预警","裂纹预警","裂纹预警","开始出土","上冲","完全长出_复用此帧保持","回收","回收","回收","回收","残留裂缝","裂缝消退","退场完成"],"heavy")
	await export_unit("tracking_short","03_追踪根簇_单轮变化",[38,45,38],0.6,[0.0,0.2,0.4,0.6,0.65,0.69,1.24,1.29,1.34,1.39,1.48,1.65,1.93],["锁点预警","锁点预警","锁点预警","开始破土","上冲","根簇长成_复用此帧保持","回收","回收","回收","回收","残留裂缝","裂缝消退","退场完成"],"tracking")
	await export_unit("tide_tile","04_全场根潮_单块变化",[112,112,112],1.0,[0.0,0.25,0.5,0.75,1.0,1.025,1.055,1.09,1.64,1.69,1.74,1.79,1.9,2.1,2.33],["地面预警","地面预警","地面预警","地面预警","开始破土","上冲","上冲","根潮峰值_复用此帧保持","回收","回收","回收","回收","残留裂缝","裂缝消退","退场完成"],"tide")
	await export_unit("decoy_cluster","05_破解终击_聚向分身",[38,76,112,76,38],1.0,[0.0,0.25,0.5,0.75,1.0,1.025,1.055,1.09,1.64,1.69,1.74,1.79,1.9,2.1,2.33],["分身脚下预警","分身脚下预警","分身脚下预警","分身脚下预警","开始聚束","上冲集束","上冲集束","集束峰值_复用此帧保持","回收","回收","回收","回收","残留裂缝","裂缝消退","退场完成"],"tide",true)
	var file := FileAccess.open(output.path_join("capture_manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"根阶段概念特效短段，战斗逻辑待实现","world_units_per_pixel":1.4,"clips":clips},"\t"));file.close()
	var unchanged := FileAccess.file_exists(SaveProgressService.SAVE_PATH) == existed and (not existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved)
	current_scene = null; viewport.free(); room.free()
	print("ROOT SHORT CAPTURE: ","OK" if unchanged else "SAVE CHANGED")
	quit(0 if unchanged else 1)

# Offline conversion for old capture manifests; the game consumes only physical clip IDs.
func show_archived_pose(animation: String, source_frame: int, reference_time: float) -> void:
	if DeerActionLibrary.clips().has(animation):
		deer._show_clip(StringName(animation),source_frame,reference_time)
		return
	for id: String in DeerActionLibrary.clips():
		var clip := DeerActionLibrary.clip(StringName(id))
		if clip.source == animation and source_frame >= int(clip.source_first) and source_frame <= int(clip.source_last):
			deer._show_clip(StringName(id),source_frame-int(clip.source_first),reference_time)
			return
	assert(false,"Unmapped archived body reference")
