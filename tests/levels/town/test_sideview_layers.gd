extends SceneTree

## 横版场景的层号关系 + 城镇 NPC 的序列帧节奏。
##
## 这两件事都属于「数值关系」而不是「好不好看」，所以放进自动化：
##   · 层号必须严格错开。2026-09-22 主角和 NPC 都是 10，同层时按加入顺序画，
##     NPC 后加进来 → 主角被盖住，而这个 bug 只有站到 NPC 旁边才看得见。
##   · 城镇 NPC 的待机是微动，速度走 TownNpcAnim 的全局值，
##     不能再出现某个 NPC 自己写 6 fps 播得像抽搐。
##
## 用法：homeing-star-test/run-tests.ps1 -Test test_sideview_layers
## 摆位好不好看、挡没挡住，仍然由人开游戏看——这里只管数值关系。

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  [ ok ] ", message)
	else:
		_failures += 1
		print("  [FAIL] ", message)


## 一个节点最终落在第几层：把 z_as_relative 的祖先层号一路加上去。
func effective_z(node: CanvasItem) -> int:
	var total := 0
	var current: Node = node
	while current is CanvasItem:
		var item := current as CanvasItem
		total += item.z_index
		if not item.z_as_relative:
			break
		current = item.get_parent()
	return total


func labelled(node: CanvasItem) -> String:
	if node == null:
		return "（不存在）"
	return "%s(z=%d 实际=%d)" % [node.name, node.z_index, effective_z(node)]


func run() -> void:
	await _check_player_owns_his_layer()
	await _check_town_layer_order()
	await _check_battle_room_layer_order()
	await _check_town_npc_tempo()

	print("")
	print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## 主角的层号写在主角自己身上：新场景忘了设也不会被 NPC 盖住。
func _check_player_owns_his_layer() -> void:
	print("[1] 主角自己认领层号（不依赖场景设置）")
	var player := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate()
	player.set("world_min_x", -400.0)
	player.set("world_max_x", 400.0)
	root.add_child(player)
	await process_frame
	check(player.z_index == SideviewLayers.PLAYER,
		"单独实例化的主角也在 PLAYER 层：%s" % labelled(player))
	player.queue_free()
	await process_frame


func _check_town_layer_order() -> void:
	print("[2] 归航镇：主角压在 NPC / 场景道具之上，仍在屏幕边缘前景框之下")
	var town := (load("res://scenes/levels/town/homeward_town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world: Node2D = town.get("world_root")
	var player: Node2D = town.get("player")
	var maidashu: Node2D = world.get_node_or_null("MaidaShu")
	var master: Node2D = world.get_node_or_null("Master")
	var crate: Node2D = world.get_node_or_null("OpeningCrateStack")
	var left_frame: Node2D = world.get_node_or_null("LeftEdgeFrame")

	check(player != null and maidashu != null and master != null,
		"镇上的人物都在（主角 / 麦大叔 / 师傅）")
	check(left_frame != null, "前景框在（有名字，能按名字查层号）")
	if player == null or maidashu == null or master == null:
		town.queue_free()
		return

	print("      主角 %s" % labelled(player))
	print("      麦大叔 %s" % labelled(maidashu))
	print("      师傅 %s" % labelled(master))
	if crate != null:
		print("      木箱 %s" % labelled(crate))
	if left_frame != null:
		print("      前景框 %s" % labelled(left_frame))

	check(player.z_index == SideviewLayers.PLAYER, "主角是 PLAYER 层")
	check(maidashu.z_index == SideviewLayers.NPC, "麦大叔是 NPC 层")
	check(master.z_index == SideviewLayers.NPC, "师傅是 NPC 层")
	check(player.z_index != maidashu.z_index,
		"NPC 与主角不同层（同层会被加入顺序左右）")
	check(effective_z(player) > effective_z(maidashu),
		"主角压在麦大叔之上（%d > %d）" % [effective_z(player), effective_z(maidashu)])
	check(effective_z(player) > effective_z(master),
		"主角压在师傅之上（%d > %d）" % [effective_z(player), effective_z(master)])
	if left_frame != null:
		check(effective_z(player) < effective_z(left_frame),
			"主角仍在前景框之下（%d < %d）——没被提到最上面"
			% [effective_z(player), effective_z(left_frame)])

	# 开场木箱是第 2 步教学的临时道具：那条教学做过了它就不存在，跳过即可。
	if crate != null:
		check(effective_z(player) > effective_z(crate),
			"主角压在木箱之上（%d > %d）" % [effective_z(player), effective_z(crate)])
	else:
		print("      （木箱不存在：跳跃教学已完成，属正常）")

	town.queue_free()
	await process_frame


func _check_battle_room_layer_order() -> void:
	print("[3] 教学战房间：主角压在木桩 / 师傅 BOSS 之上（同一套层号）")
	var battle := (load("res://scenes/levels/tutorial/tutorial_battle_room.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	var lan: Node2D = battle.get_node_or_null("Lan")
	var boss: Node2D = battle.get_node_or_null("MasterBoss")
	var dummy: Node2D = battle.get_node_or_null("TrainingDummy")
	check(lan != null and boss != null and dummy != null, "战斗房里三个角色都在")
	if lan == null or boss == null or dummy == null:
		battle.queue_free()
		return

	print("      岚 %s" % labelled(lan))
	print("      师傅 BOSS %s" % labelled(boss))
	print("      木桩 %s" % labelled(dummy))

	check(lan.z_index == SideviewLayers.PLAYER, "岚在战斗房里也是 PLAYER 层")
	check(effective_z(lan) > effective_z(boss),
		"岚压在师傅 BOSS 之上（%d > %d）" % [effective_z(lan), effective_z(boss)])
	check(effective_z(lan) > effective_z(dummy),
		"岚压在木桩之上（%d > %d）" % [effective_z(lan), effective_z(dummy)])

	battle.queue_free()
	await process_frame


func _check_town_npc_tempo() -> void:
	print("[4] 城镇 NPC 的序列帧节奏（全局规则）")
	var town := (load("res://scenes/levels/town/homeward_town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world: Node2D = town.get("world_root")
	var maidashu: Node2D = world.get_node_or_null("MaidaShu")
	var master: Node2D = world.get_node_or_null("Master")
	if maidashu == null or master == null:
		check(false, "镇上两个 NPC 都在")
		town.queue_free()
		return

	var maid_frames: SpriteFrames = (maidashu.get_node("AnimatedSprite2D") as AnimatedSprite2D).sprite_frames
	var master_frames: SpriteFrames = (master.get_node("AnimatedSprite2D") as AnimatedSprite2D).sprite_frames

	check(is_equal_approx(maid_frames.get_animation_speed(&"idle"), TownNpcAnim.IDLE_FPS),
		"麦大叔 idle = 全局节奏 %.1f fps（慢下来之前是 6.0）"
		% maid_frames.get_animation_speed(&"idle"))
	# 对照的是**素材原始节奏 6.0**，不是某个具体数字——
	# 全局值本身是肉眼定的（6 → 2 → 4），写死数值会让每次调节奏都来改测试。
	check(maid_frames.get_animation_speed(&"idle") < 6.0, "麦大叔 idle 确实比原来的 6.0 慢")
	check(maid_frames.get_animation_loop(&"idle"), "麦大叔 idle 仍然循环")
	check(maid_frames.get_frame_count(&"idle") == 8, "麦大叔 idle 仍然是 8 帧（只改速度没丢帧）")

	check(is_equal_approx(master_frames.get_animation_speed(&"idle"), TownNpcAnim.IDLE_FPS),
		"师傅 idle = 全局节奏 %.1f fps" % master_frames.get_animation_speed(&"idle"))
	check(master_frames.get_animation_speed(&"drink") > TownNpcAnim.IDLE_FPS,
		"师傅 drink 是一次性动作、不跟 idle 一起变慢（%.1f fps）"
		% master_frames.get_animation_speed(&"drink"))
	check(not master_frames.get_animation_loop(&"drink"), "师傅 drink 仍然是一次性动作")

	town.queue_free()
	await process_frame
