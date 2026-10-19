extends SceneTree

## 「第三栋房子旁边那个小孩」的代码级回归检查。
##
## 覆盖三件事：
##   1. 小孩节点自己：层号 / 站位 / 缩放（= 岚的 2/3 高）/ 四帧待机走全局节奏；
##   2. 气泡锚点算得对不对（在头顶、且高度随缩放等比缩）；
##   3. 开场引导第 6 步：走到跟前才喊、喊完要等退远才能再喊（迟滞）；
##      以及任务面板上「初见归航星」这条确实列出来了、且小孩这件事是它的第一段落
##      （**不是**一条独立任务 —— 那个从属关系被用户纠正过一次）。
##
## ⚠️ **全程不写盘**：存档状态是往 autoload 的 SaveProgress **内存**里注入的假 config
##    （只 set _config / _loaded，从不调 mark_completed）。
##    这一点很重要——开发机上跑测试时用户常常正开着游戏，真实存档不能被碰。
##
## 跑法：homeing-star-test/run-tests.ps1 -Test test_child_npc

const TOWN_SCENE := "res://scenes/sideview/homeward_town.tscn"

## 岚 idle 一帧 46×55、场景缩放 1.5 → 画出来 82.5 px 高。小孩按用户要求是它的 2/3。
const LAN_RENDERED_HEIGHT := 55.0 * 1.5

var _checks := 0
var _failures := 0

var _save: SaveProgressService


## autoload 的 _ready 在 _initialize 阶段还没跑完（踩过），所以推迟到第一帧再开跑。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save = root.get_node_or_null("SaveProgress") as SaveProgressService
	check(_save != null, "SaveProgress autoload 在位")
	if _save == null:
		return _finish()

	await _check_child_node()
	await _check_call_proximity()
	_check_quest_entry()
	_finish()


# ---------------------------------------------------------------------------
# 1. 小孩节点
# ---------------------------------------------------------------------------

func _check_child_node() -> void:
	print("[1] 小孩节点")
	_set_progress(_state_before_climb())

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var child := world.get_node_or_null("ChildNpc") as ChildNpc
	check(child != null, "归航镇里存在 ChildNpc")
	if child == null:
		town.queue_free()
		await process_frame
		return

	check(child.z_index == SideviewLayers.NPC,
		"小孩在 NPC 层（%d），低于主角 %d" % [child.z_index, SideviewLayers.PLAYER])

	var constants: Dictionary = town.get_script().get_script_constant_map()
	var expected_x: float = float(constants["CHILD_NPC_X"])
	check(is_equal_approx(child.position.x, expected_x),
		"横坐标取常量的值（%.1f = %.1f）" % [child.position.x, expected_x])
	check(is_equal_approx(child.position.y, SideviewMapLayout.GROUND_BASELINE_Y),
		"脚底踩在主街行走线上（%.1f）" % child.position.y)

	# 站位：他要站在导航馆（第三栋房子）旁边。两个边界都拿建筑常量反推，不写死坐标 ——
	# 以后改楼的贴图位置或缩放，这两条不会跟着失效（这正是它们比"写死一个数"值钱的地方）。
	var hall_left: float = float(constants["NAVIGATION_HALL_LEFT_X"])
	check(child.position.x > hall_left,
		"站在导航馆本体左沿之内（%.1f > %.1f）" % [child.position.x, hall_left])
	check(child.position.x - hall_left < 60.0,
		"离楼左沿很近，读作「站在楼旁边」（%.1f px）" % (child.position.x - hall_left))

	# 缩放：验的是**他看到多大**，而不是只验那个乘数。
	# 素材帧内内容高 = 内容底 125 − 头顶 6 + 1 = 120。
	var source_height := ChildNpc.CONTENT_BOTTOM_Y - ChildNpc.HEAD_TOP_Y + 1.0
	check(is_equal_approx(source_height, 120.0), "素材内容高 120 px（%.0f）" % source_height)
	var rendered_height := source_height * child.scale.y
	var target := LAN_RENDERED_HEIGHT * 2.0 / 3.0
	print("      小孩画出 %.1f px 高；岚画出 %.1f px；目标是 %.1f px"
		% [rendered_height, LAN_RENDERED_HEIGHT, target])
	check(absf(rendered_height - target) < 0.5,
		"身高 = 岚的 2/3（%.1f ≈ %.1f）" % [rendered_height, target])
	check(rendered_height < LAN_RENDERED_HEIGHT * 0.8, "确实明显比岚小")

	var sprite := child.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var frames := sprite.sprite_frames
	check(frames.get_frame_count(&"idle") == 4, "四帧待机（%d）" % frames.get_frame_count(&"idle"))
	check(is_equal_approx(frames.get_animation_speed(&"idle"), TownNpcAnim.IDLE_FPS),
		"速度走全局规则 %.1f fps" % frames.get_animation_speed(&"idle"))
	check(frames.get_animation_loop(&"idle"), "待机是循环")
	check(frames.get_frame_texture(&"idle", 0) is AtlasTexture, "帧是从图集切出来的")

	# 帧内内容底部 → 世界坐标，应该正好落在 NPC 原点上（原点又摆在地面线上）。
	var feet_offset := (ChildNpc.CONTENT_BOTTOM_Y - float(ChildNpc.FRAME_SIZE.y) * 0.5
		+ sprite.position.y) * child.scale.y
	check(absf(child.global_position.y + feet_offset - SideviewMapLayout.GROUND_BASELINE_Y) < 0.5,
		"脚底正好贴在原点上（偏差 %.2f px）" % (child.global_position.y + feet_offset
			- SideviewMapLayout.GROUND_BASELINE_Y))

	# 气泡锚点：头顶正中再往上 BUBBLE_GAP。
	var anchor := child.resolve_bubble_anchor()
	print("      小孩头顶锚点 = (%.1f, %.1f)" % [anchor.x, anchor.y])
	check(anchor.y < child.global_position.y, "锚点在原点之上（头顶）")
	check(absf(anchor.x - child.global_position.x) < 2.0,
		"锚点横向对在小孩身上（偏 %.2f px）" % (anchor.x - child.global_position.x))
	# 头顶到内容底部是 119 个原尺寸像素，全程被缩放；最后那个 BUBBLE_GAP(6) 加在变换之外，
	# **不参与缩放** —— 和吃饭那两位是同一条规则。
	var expected_gap := (ChildNpc.CONTENT_BOTTOM_Y - ChildNpc.HEAD_TOP_Y) * child.scale.y \
		+ ChildNpc.BUBBLE_GAP
	check(is_equal_approx(child.global_position.y - anchor.y, expected_gap),
		"头顶锚点高度随缩放等比缩（%.2f）" % (child.global_position.y - anchor.y))

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 2. 走近才喊 + 迟滞
# ---------------------------------------------------------------------------

func _check_call_proximity() -> void:
	print("[2] 走近才喊 + 迟滞")
	_set_progress(_state_before_climb())

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var guide := town.get("opening_guide") as OpeningGuide
	var child := world.get_node_or_null("ChildNpc") as ChildNpc
	var player := town.get("player") as Node2D
	check(guide != null, "归航镇挂上了开场引导")
	check(child != null and player != null, "小孩与主角都在位")
	if guide == null or child == null or player == null:
		town.queue_free()
		await process_frame
		return

	check(guide.stage == OpeningGuide.Stage.CHILD_CALL,
		"前面都做过 → 引导停在等小孩开口这一档（实际 %d）" % guide.stage)
	check(OpeningGuide.CHILD_CALL_LINE == "岚！岚！帮我拿一下那个！",
		"台词是用户给的原文（%s）" % OpeningGuide.CHILD_CALL_LINE)
	check(OpeningGuide.CHILD_CALL_REARM_RANGE > OpeningGuide.CHILD_CALL_RANGE,
		"迟滞距离必须大于触发距离（%.0f > %.0f）" % [
			OpeningGuide.CHILD_CALL_REARM_RANGE, OpeningGuide.CHILD_CALL_RANGE,
		])

	var bubble := world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble == null or not bubble.visible, "玩家还在出生点，气泡没冒出来")

	# 走到小孩跟前。
	player.position.x = child.position.x
	await process_frame
	await process_frame
	# 锚点要在**这一刻**取：它按世界坐标算，而镜头（world_root.position）已经跟着玩家滚过了。
	var anchor := child.resolve_bubble_anchor()
	bubble = world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble != null and bubble.visible, "走到跟前，气泡冒出来了")
	if bubble != null:
		var label := bubble.get_node_or_null("BubblePanel/BubbleText") as Label
		check(label != null and label.text == OpeningGuide.CHILD_CALL_LINE,
			"气泡里就是那句话（%s）" % (label.text if label != null else "<没有 Label>"))

		# ⚠️⚠️ **这条是回归线，别删也别放宽。**
		# 气泡挂在 world_root 底下，`position` 是父节点局部坐标；而 NPC 给的锚点是**世界坐标**。
		# 少了那一步换算，气泡就会偏掉"镜头已经滚过的距离"：小孩在世界 x 1556，
		# 站在他跟前时镜头已滚过 916 px，气泡被画到屏幕左边 276 px **之外**，
		# 一个字都看不见 —— 玩家的感受就是"这个小孩根本没喊话"（2026-09-22 的实况）。
		# 所以只验 visible / 文字是抓不到它的，**必须验全局位置**。
		check(bubble.global_position.distance_to(anchor) < 1.0,
			"气泡尾巴落在小孩头顶锚点上（偏 %.1f px）" % bubble.global_position.distance_to(anchor))

		# 而且得真的在画面里：锚点在屏幕外的话，上面那条就算过了也没用。
		var screen := root.get_visible_rect()
		var panel := bubble.get_node_or_null("BubblePanel") as Control
		check(screen.has_point(anchor),
			"锚点落在画面内（%.1f, %.1f 在 %s 里）" % [anchor.x, anchor.y, screen])
		if panel != null:
			var panel_rect := panel.get_global_rect()
			print("      屏幕 = %s，气泡底板 = %s" % [screen, panel_rect])
			check(screen.encloses(panel_rect),
				"整块气泡底板都在画面内（不越出左右上下边缘）")

	check(not bool(guide.get("_child_call_armed")), "喊过一次之后闸门关上（迟滞生效）")

	# 只退到触发圈边上：还不该重新上膛。
	player.position.x = child.position.x + OpeningGuide.CHILD_CALL_RANGE + 10.0
	await process_frame
	await process_frame
	check(not bool(guide.get("_child_call_armed")), "刚出触发圈还不重新上膛")

	# 退到迟滞距离之外：重新上膛。
	player.position.x = child.position.x + OpeningGuide.CHILD_CALL_REARM_RANGE + 10.0
	await process_frame
	await process_frame
	check(bool(guide.get("_child_call_armed")), "退到迟滞距离之外 → 重新上膛")

	# 再走回去：应该又喊一次（他要的东西一直没拿到）。
	player.position.x = child.position.x
	await process_frame
	await process_frame
	check(not bool(guide.get("_child_call_armed")), "再走近 → 又喊了一次")

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 3. 任务面板上的这一条
# ---------------------------------------------------------------------------

func _check_quest_entry() -> void:
	print("[3] 任务面板")
	var quest_log := root.get_node_or_null("QuestLog") as QuestLogService
	check(quest_log != null, "QuestLog autoload 在位")
	if quest_log == null:
		return

	var view := quest_log.get_track_view()
	var quests: Array = view.get("quests", [])
	var found := false
	var titles: Array = []
	for quest in quests:
		titles.append(String(quest["title"]))
		check(not quest.has("completed"), "面板数据里没有 completed 字段（做完的不上榜）")
		# ⚠️ 小孩这件事**不是一条独立任务**：它是「初见归航星」的第一个子任务
		#    （用户 2026-09-22 纠正的从属关系）。所以这里找的是「初见归航星」，
		#    并顺带钉住"面板上没有第二条叫「小孩的风筝」的任务"。
		if String(quest["title"]) != "初见归航星":
			continue
		found = true
		check(int(quest["done_count"]) == 0 and int(quest["total_count"]) == 4,
			"初见归航星 0/4（%d/%d）" % [int(quest["done_count"]), int(quest["total_count"])])
		check(String(quest["current_text"]) == "顺着墙爬到二楼，帮小孩把风筝拿下来",
			"当前该做的一步就是爬墙拿风筝（%s）" % String(quest["current_text"]))
		var segments: Array = quest["segments"]
		check(segments.size() >= 1 and String(segments[0]["display_title"]) == "第一段落 · 认识攀爬",
			"它作为第一段落「认识攀爬」挂在这条任务下（%s）" % str(
				[] if segments.is_empty() else String(segments[0]["display_title"])))
	check(found, "「初见归航星」列在当前小节里（%s）" % str(titles))
	check(not titles.has("小孩的风筝"),
		"没有单独一条叫「小孩的风筝」的任务（%s）" % str(titles))
	# 前一档存档里「麦大叔的早饭」三步全做完了 —— 它必须整条消失，而不是留在列表里打勾。
	check(not titles.has("麦大叔的早饭"),
		"做完的「麦大叔的早饭」不在列表里（%s）" % str(titles))


# ---------------------------------------------------------------------------
# 帮手
# ---------------------------------------------------------------------------

## 「前面全做过、只差攀爬」这一档。三处都用它，写一次省得改漏。
func _state_before_climb() -> Array:
	return [
		SaveProgressService.TUTORIAL_MOVE,
		SaveProgressService.TUTORIAL_JUMP,
		SaveProgressService.TUTORIAL_BREAKFAST,
		SaveProgressService.STORY_EATING_TALK,
	]


## 往 autoload 的内存里塞一份假的存档内容。
##
## 直接改 `_config` / `_loaded` 两个成员：`has_completed()` 走的正是它们，
## 所以查询会看到 given 的这些 id，而**磁盘上的 progress.cfg 一个字节都不会动**。
func _set_progress(completed: Array) -> void:
	var config := ConfigFile.new()
	for id: StringName in completed:
		config.set_value(SaveProgressService.PROGRESS_SECTION, String(id), true)
	_save.set("_config", config)
	_save.set("_loaded", true)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  [ ok ] ", label)
	else:
		_failures += 1
		print("  [FAIL] ", label)


func _finish() -> void:
	print("")
	print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
