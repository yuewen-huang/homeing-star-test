extends "../../support/harness.gd"

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var save := use_memory_progress()
	(root.get_node("QuestLog") as QuestLogService)._save = save
	for fact: StringName in [SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST, SaveProgressService.QUEST_CHILD_KITE_PICKED]:
		save.mark_completed(fact)
	save.mark_completed(SaveProgressService.TUTORIAL_CLIMB)
	var town: Node2D = load("res://scenes/levels/town/homeward_town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	await process_frame
	var player := town.get("player") as LanPlayer
	var door_x := float(town.NAVIGATION_DOOR_X)
	player.position = Vector2(door_x, town.STREET_BASELINE)
	await process_frame
	check(town.get("hall_entry_hint") != null, "正门应显示 E 提示")
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	town._unhandled_input(e)
	check(save.has_completed(SaveProgressService.QUEST_ENTER_HALL), "进入归航厅应记录进度")
	await create_timer(3.0).timeout
	check(current_scene != null and current_scene.name == "NavigationHallEntryComic",
		"应先进入逐张播放的转场漫画")
	var comic := current_scene
	for index in range(1, 5):
		comic._input(e)
		if index < 4:
			await create_timer(0.3).timeout
			check(comic.get("panel_index") == index, "漫画应切到下一张分镜")
	await create_timer(3.0).timeout
	check(current_scene != null and current_scene.name == "NavigationHallPlaceholder",
		"看完漫画后应进入临时房间")
	var room := current_scene
	var dialogue := room.get("navigator_dialogue") as TutorialDialogue
	check(dialogue != null and dialogue.opened, "漫画结束后应自动与导航员对话")
	check(dialogue.get_line_progress() == Vector2i(0, 11), "导航员对话应有 11 句")
	var portrait_sizes: Dictionary = {}
	for _index in range(11):
		var name_text := dialogue._name_label.text
		var portrait := dialogue._portrait.texture
		check(portrait != null and portrait.get_size() == Vector2(120, 107) and portrait.resource_path.contains("/portraits/dialogue_fit/"), "归航厅表情应直接使用校准后的头像画布")
		check(dialogue._portrait_clip.position == TutorialDialogue.BOX_POSITION
			+ (TutorialDialogue.CUTOUT_LEFT.position if name_text == "岚"
			else TutorialDialogue.CUTOUT_RIGHT.position), "头像必须留在说话人对应的框内")
		check(is_equal_approx(dialogue._portrait.position.y + dialogue._portrait.size.y,
			dialogue._portrait_clip.size.y), "头像底边必须贴齐头像框底边")
		if portrait_sizes.has(name_text):
			check(dialogue._portrait.size.is_equal_approx(portrait_sizes[name_text]),
				"同一角色切换表情时头像大小不能跳动")
		else:
			portrait_sizes[name_text] = dialogue._portrait.size
		dialogue.advance()
	check(save.has_completed(SaveProgressService.QUEST_FIRST_SIGHT_STEP),
		"与导航员聊完后应保存当前任务进度")
	check(save._config.get_value(SaveProgressService.PROGRESS_SECTION, String(SaveProgressService.QUEST_FIRST_SIGHT_STEP), false), "导航员对话完成状态应通过存档服务结算" )
	var next_quest_found := false
	var quest_view := (root.get_node("QuestLog") as QuestLogService).get_track_view()
	for quest: Dictionary in quest_view.get("quests", []):
		if quest["id"] == QuestCatalog.QUEST_HALL_NEXT:
			next_quest_found = true
	check(next_quest_found, "对话结束后应显示自由探索的后续任务")
	var navigator := room.get("navigator") as NavigatorNpc
	check(navigator != null and navigator.sprite.sprite_frames.get_frame_count(&"idle") == 4,
		"球体左侧应有四帧导航员")
	check(navigator.position == Vector2(575.0, 490.0), "导航员应站在球体左侧靠后的红线位置")
	var art_paths: Array[String] = []
	var art_root := room.get("art_root") as Node2D
	var glow := art_root.get_node_or_null("OrbGlow") as ColorRect
	check(glow != null and glow.position + glow.size * 0.5 == Vector2(803.0, 282.0),
		"呼吸闪光应落在球体右上方的亮点")
	for child in art_root.get_children():
		if child is Sprite2D:
			art_paths.append((child as Sprite2D).texture.resource_path)
	check(art_paths.size() == 5, "归航厅应加载两张连续远景和三层厅内素材")
	check(art_paths.has("res://assets/levels/navigation_hall/environment/far_day.png"),
		"归航厅远景默认应为白天")
	var far_tiles: Array = room.get("far_day_tiles")
	check(far_tiles.size() == 2, "远景需要两张连续图片")
	check(is_equal_approx(far_tiles[0].position.x - far_tiles[1].position.x,
		far_tiles[0].texture.get_width()), "两张远景必须首尾相接")
	var far_x_before: float = far_tiles[0].position.x
	room._process(1.0)
	check(is_equal_approx(far_tiles[0].position.x - far_x_before, 2.0),
		"白天远景应缓慢水平滚动")
	var room_player := room.get("player") as LanPlayer
	check(is_equal_approx(room_player.position.y, 555.0), "归航厅必须沿用全项目行走基线")
	room_player.position.x = 1500.0
	room._process(0.0)
	(room.get("npc_chatter") as TownNpcChatter)._process(0.0)
	check((room.get("world_root") as Node2D).position.x < 0.0,
		"走向大厅右侧时镜头应跟随")
	room_player.position.x = -50.0
	room._process(0.0)
	check((room.get("world_root") as Node2D).position.x > 0.0,
		"走向大厅左侧时镜头应跟随")
	room_player.position.x = 560.0
	(room.get("npc_chatter") as TownNpcChatter)._process(0.0)
	var bubble := (room.get("world_root") as Node2D).get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble != null and bubble.visible, "任务结束后再经过导航员应有日常气泡")
	room_player.position = Vector2(room.EXIT_X, room.FLOOR_Y)
	await process_frame
	await process_frame
	var exit_prompt := room.get("exit_hint") as MapPortalPrompt
	if exit_prompt == null or not exit_prompt.can_interact():
		push_error("返回归航镇的传送门应在靠近后显示呼吸 E 并允许交互")
		quit(1)
		return
	var return_glow := (room.get("world_root") as Node2D).get_node_or_null(
		"TownReturnPortalGlow") as ColorRect
	check(return_glow != null, "返回归航镇的落点应有淡蓝呼吸光晕")
	check(is_equal_approx(
		return_glow.position.x + return_glow.size.x * 0.5,
		float(room.EXIT_X)
	), "归航镇返回交互点应对齐门口")
	room._unhandled_input(e)
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == "res://scenes/story/comics/navigation_hall_exit_comic.tscn", "首次离厅先播放离场漫画")
	var exit_comic := current_scene as ComicPlayer
	if exit_comic == null:
		finish("NAVIGATION HALL ENTRY")
		return
	for index in exit_comic._frames.size():
		exit_comic._input(e)
		await create_timer(0.3).timeout
	await create_timer(3.0).timeout
	check(current_scene != null and current_scene.name == "HomewardTown",
		"应返回归航镇")
	var returned_player := current_scene.get("player") as LanPlayer
	check(absf(returned_player.position.x - (door_x + 90.0)) < 2.0,
		"回镇后应出现在归航厅门口附近")
	var revisit: Node2D = (load(
		"res://scenes/levels/navigation_hall/navigation_hall.tscn") as PackedScene).instantiate()
	root.add_child(revisit)
	await process_frame
	check(revisit.get("navigator_dialogue") == null, "重进归航厅不应重播对话")
	revisit.queue_free()
	print("归航厅入场、返回与任务进度通过")
	expect_save_untouched()
	finish("NAVIGATION HALL ENTRY")
