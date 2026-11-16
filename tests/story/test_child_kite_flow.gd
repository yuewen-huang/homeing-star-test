extends "../support/harness.gd"

const STAGED_VIEW := preload("res://scripts/ui/main_story_dialogue.gd")


func run() -> void:
	var save := use_memory_progress()
	for fact: StringName in [SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST, SaveProgressService.STORY_EATING_TALK]:
		save.mark_completed(fact)
	(root.get_node("QuestLog") as QuestLogService)._save = save
	var ui := root.get_node("InventoryScreen") as InventoryUI
	ui._save = save
	var town: Node2D = load("res://scenes/levels/town/homeward_town.tscn").instantiate()
	root.add_child(town)
	await process_frame
	var player := town.get("player") as LanPlayer
	var quest := town.get_node("ChildKiteQuest") as ChildKiteQuest
	player.position = town.child_npc.position
	await wait_frames(3)
	var call_bubble := quest.world_root.get_node_or_null(^"WorldBubble") as CharacterBubble
	check(call_bubble != null and call_bubble.visible
		and call_bubble._label.text == "岚！岚！帮我拿一下那个！", "靠近小孩仍能听到原有求助")
	check(ui != null and ui._slots.size() == 32, "背包有三页共用的 8×4 程序格子")
	var bag_rect := ui._content.get_global_rect()
	var screen := root.get_visible_rect()
	check(screen.encloses(bag_rect), "背包完整落在画面内")
	check(bag_rect.get_center().distance_to(screen.get_center()) < 1.0, "背包在画面正中")
	var b_key := InputEventKey.new()
	b_key.physical_keycode = KEY_B
	b_key.pressed = true
	ui._unhandled_input(b_key)
	check(ui.visible, "按 B 打开背包")
	ui._select_category(1)
	check(ui._title.text == "消耗品", "切换到消耗品页")
	ui._select_category(2)
	check(ui._title.text == "任务道具", "切换到任务道具页")
	ui._select_category(0)
	check(quest._kite != null, "未拾取时二楼有风筝")
	if quest._kite == null:
		quit(1)
		return
	player.position = quest._kite.position
	await process_frame
	check(save.get_item_count(ItemCatalog.CHILD_KITE) == 1, "靠近后自动获得风筝")
	check(save.has_completed(SaveProgressService.QUEST_CHILD_KITE_PICKED), "拾取步骤完成")
	check(quest._kite == null, "拾取后场景风筝消失")
	check(not save.has_completed(SaveProgressService.TUTORIAL_CLIMB), "拾取后任务尚未完成")
	var view := (root.get_node("QuestLog") as QuestLogService).get_track_view()
	check(String(view["quests"][0]["current_text"]).contains("交还"), "任务提示切换为交还小孩")
	ui._select_category(2)
	check(ui._slots[0].has_meta("item_id"), "风筝显示在任务道具页")
	ui._on_slot_hover(ui._slots[0])
	check(ui._tooltip.visible and ui._tooltip_usage.text.contains("交还"), "悬停说明包含用途")
	ui.close_inventory()
	player.position = (town.get("child_npc") as ChildNpc).position
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	quest._unhandled_input(event)
	var dialogue := quest._dialogue
	check(dialogue != null and dialogue is STAGED_VIEW and dialogue.opened,
		"回到小孩身边按 E 进入新版交还对话")
	if dialogue != null:
		check(dialogue.get_line_progress() == Vector2i(0, 3), "交还仍有原来的三句")
		var child_performer = dialogue._actors[&"child"]
		var lan_listener = dialogue._actors[&"lan"]
		check(child_performer.current.texture != null and child_performer.current.flip_h,
			"小孩要抱着风筝转向岚")
		dialogue._complete_line()
		check(lan_listener.current.texture.resource_path.ends_with("caught_off_guard.png"),
			"小孩提到风时，岚在开口前先有反应")
		await capture_dialogue("05-kite-return")
		dialogue.advance()
		dialogue.advance()
		check(child_performer.current.texture.resource_path.ends_with("kite_explaining.png"),
			"最后一句切到小孩抱风筝解释的姿势")
		check(save.get_item_count(ItemCatalog.CHILD_KITE) == 1
			and not save.has_completed(SaveProgressService.TUTORIAL_CLIMB), "说完前仍持有风筝")
		dialogue.advance()
	check(save.get_item_count(ItemCatalog.CHILD_KITE) == 0, "交还后风筝从背包移除")
	check(save.has_completed(SaveProgressService.TUTORIAL_CLIMB), "交还后任务完成")
	check(quest._dialogue == null and not player.input_frozen, "交还后恢复操作")
	quest._unhandled_input(event)
	check(quest._dialogue == null, "交还过后再次按 E 不会重播")
	expect_save_untouched()
	finish("CHILD KITE FLOW")


func capture_dialogue(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"保存风筝交还实机画面")
