extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run_test")

func check(condition: bool, message: String) -> void:
	if condition:
		print("[ ok ] ", message)
	else:
		failures += 1
		push_error(message)

func run_test() -> void:
	var save := root.get_node("SaveProgress") as SaveProgressService
	var ui := root.get_node("InventoryScreen") as InventoryUI
	var town: Node2D = load("res://scenes/sideview/homeward_town.tscn").instantiate()
	root.add_child(town)
	await process_frame
	var player := town.get("player") as LanPlayer
	var quest := town.get_node("ChildKiteQuest") as ChildKiteQuest
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
	check(ui._tooltip.visible and ui._tooltip_text.text.contains("交还"), "悬停说明包含用途")
	player.position = (town.get("child_npc") as ChildNpc).position
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	quest._unhandled_input(event)
	check(quest._dialogue != null and quest._dialogue.opened, "回到小孩身边按 E 开始交还对话")
	if quest._dialogue != null:
		quest._dialogue.advance()
		quest._dialogue.advance()
	check(save.get_item_count(ItemCatalog.CHILD_KITE) == 0, "交还后风筝从背包移除")
	check(save.has_completed(SaveProgressService.TUTORIAL_CLIMB), "交还后任务完成")
	print("结果：%d 项失败" % failures)
	quit(1 if failures > 0 else 0)
