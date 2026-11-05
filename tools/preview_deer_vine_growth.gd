extends SceneTree
const Plant = preload("res://scripts/bosses/deer/deer_vine_growth.gd")
var room: BossDevelopmentRoom
var deer: Node2D
var plants: Array[Node2D] = []
var age := 0.0
var capture_index := 0
var capture_dir := ""
var elapsed := 0.0

func _initialize() -> void: call_deferred("open_room")

func open_room() -> void:
	DisplayServer.window_set_title("鹿 · 扎根生长样片 / 根部固定 · 逐节展开")
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_duel_adapter.gd"): room.select_boss(i)
	deer=room.adapter.boss
	deer.set_physics_process(false)
	deer.position.x=640
	deer.direction=-1
	room.player.position.x=775
	room.set_process(false)
	room.set_physics_process(false)
	room.set_process_unhandled_key_input(false)
	room.show_grid=false
	room.queue_redraw()
	room.dummy.hide()
	room.telemetry_readout.get_parent().hide()
	# Hide combat controls: this looping anatomy study cannot launch combat groups.
	for child in room.get_children():
		if child is CanvasLayer: child.hide()
	var study_ui := CanvasLayer.new()
	room.add_child(study_ui)
	var caption := Label.new()
	caption.text="藤 · 扎根生长样片     /     自动循环 · 无伤害"
	caption.position=Vector2(24,22)
	caption.add_theme_font_size_override("font_size",20)
	caption.modulate=Color(.74,.76,.65)
	study_ui.add_child(caption)
	# Keep the existing room/character scale; the anatomy must work beside the real deer.
	for data in [[125,1,300,.20,Color(.48,.55,.42)],[1150,-1,315,.42,Color(.48,.55,.42)],[220,1,410,.53,Color.WHITE],[1050,-1,420,.78,Color.WHITE]]:
		var part := Plant.new()
		room.specimen.add_child(part)
		part.setup(Vector2(data[0],555),data[1],data[2],data[3],data[4])
		plants.append(part)
	capture_dir=OS.get_environment("HOMING_STAR_GROWTH_CAPTURE")
	print("ROOTED VINE STUDY READY: fixed roots, soil emergence, sequential botanical unfurl; no combat replacement")
	process_frame.connect(tick)

func tick() -> void:
	var dt := 1.0/60.0 if not capture_dir.is_empty() else root.get_process_delta_time()
	age+=dt
	elapsed+=dt
	for plant in plants: plant.sample(age)
	if age<.5: deer._sample_pose(&"heavy_START",age,.5)
	elif age<.8: deer._sample_pose(&"heavy_ING",age-.5,.3)
	elif age<1.22: deer._sample_pose(&"heavy_END",age-.8,.42)
	elif age<2.7: deer._show_clip_at(&"idle_ING",age-1.22,12,true)
	elif age<3.3: deer._sample_pose(&"bind_push_START",age-2.7,.6)
	else: deer._show_clip_at(&"bind_push_ING",age-3.3,12,true)
	if not capture_dir.is_empty():
		if int(round(elapsed*60))%3==0:
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(capture_dir.path_join("growth_%03d.png" % capture_index))
			capture_index+=1
		if capture_index>=122:
			print("ROOTED VINE CAPTURE COMPLETE: ",capture_index," native frames")
			process_frame.disconnect(tick)
			call_deferred("finish_capture")
	elif age>6.1: age=0

func finish_capture() -> void:
	plants.clear()
	current_scene=null
	room.free()
	await process_frame
	await process_frame
	quit()
