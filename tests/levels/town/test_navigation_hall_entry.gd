extends "../../support/harness.gd"

const STAGED_VIEW := preload("res://scripts/ui/main_story_dialogue.gd")

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
	check(room.get("navigator_dialogue") == null and room.get("star_dialogue") == null,
		"进厅后仍由玩家决定往哪里走")
	var hall_player := room.get("player") as LanPlayer
	hall_player.position.x = room.NAVIGATOR_X
	room._unhandled_input(e)
	var optional := room.get("navigator_dialogue") as TutorialDialogue
	check(optional != null and optional is STAGED_VIEW and optional.opened,
		"靠近导航员按 E 可选听新版半身对白")
	if optional != null:
		check(optional.get_line_progress() == Vector2i(0, 11), "导航员对白仍为原来的十一句")
		var attendant = optional._actors[&"navigator"]
		var lan_listener = optional._actors[&"lan"]
		check(attendant.current.texture != null and attendant.current.flip_h,
			"导航员面朝岚抬手制止")
		optional._complete_line()
		check(lan_listener.current.texture.resource_path.ends_with("caught_off_guard.png"),
			"导航员说别碰时岚先有反应")
		await capture_navigator()
		for index in 10:
			optional.advance()
		check(attendant.current.texture.resource_path.ends_with("bored.png"),
			"最后一句回到导航员等着下班的神情")
		optional.advance()
	check(not save.has_completed(SaveProgressService.QUEST_FIRST_SIGHT_STEP),
		"导航员的闲聊不能代替调查")
	hall_player.position.x = room.STAR_X
	room._unhandled_input(e)
	var dialogue := room.get("star_dialogue") as TutorialDialogue
	check(dialogue != null and dialogue.get_line_progress() == Vector2i(0, 2),
		"靠近归航星按 E 播放岚的两句调查对白")
	if dialogue != null:
		var performer = dialogue._actors[&"lan"]
		check(performer.current.texture != null and performer.current.texture.resource_path.ends_with(
			"altar_chill.png"), "岚在祭坛前先因寒气抱紧斗篷")
		dialogue.advance()
		check(performer.current.texture != null and performer.current.texture.resource_path.ends_with(
			"determined.png"), "岚决定去找师傅时换成坚定的姿势")
		dialogue.advance()
	check(save.has_completed(SaveProgressService.QUEST_FIRST_SIGHT_STEP),
		"岚调查归航星后才完成旧任务键")
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
	var town_spawn := {"x": INF}
	var record_town_spawn := func() -> void:
		if current_scene != null and current_scene.name == "HomewardTown":
			var arriving_player := current_scene.get("player") as LanPlayer
			town_spawn.x = arriving_player.position.x
	scene_changed.connect(record_town_spawn)
	room._unhandled_input(e)
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == "res://scenes/story/comics/navigation_hall_exit_comic.tscn", "首次离厅先播放离场漫画")
	var exit_comic := current_scene as ComicPlayer
	if exit_comic == null:
		scene_changed.disconnect(record_town_spawn)
		finish("NAVIGATION HALL ENTRY")
		return
	for index in exit_comic._frames.size():
		exit_comic._input(e)
		await create_timer(0.3).timeout
	await create_timer(3.0).timeout
	check(current_scene != null and current_scene.name == "HomewardTown",
		"应返回归航镇")
	scene_changed.disconnect(record_town_spawn)
	check(absf(float(town_spawn.x) - (door_x + 90.0)) < 2.0,
		"回镇出生点应在归航厅门口附近（%.1f）" % float(town_spawn.x))
	var revisit: Node2D = (load(
		"res://scenes/levels/navigation_hall/navigation_hall.tscn") as PackedScene).instantiate()
	root.add_child(revisit)
	await process_frame
	check(revisit.get("navigator_dialogue") == null and revisit.get("star_anchor") == null, "重进归航厅不应重播已经调查过的剧情")
	revisit.player.position.x = revisit.NAVIGATOR_X
	revisit._unhandled_input(e)
	var after_star := revisit.get("navigator_dialogue") as TutorialDialogue
	check(after_star != null and after_star.opened, "调查归航星之后仍可回来找导航员")
	if after_star != null:
		while after_star.opened:
			after_star.advance()
	revisit.queue_free()
	print("归航厅入场、返回与任务进度通过")
	expect_save_untouched()
	finish("NAVIGATION HALL ENTRY")


func capture_navigator() -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join("06-navigator.png")) == OK,
		"保存导航员实机画面")
