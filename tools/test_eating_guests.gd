extends SceneTree

## 「桌旁两位客人 + 闲聊 + 任务链」的代码级回归检查。
##
## 覆盖三件事：
##   1. 客人节点自己：层号 / 三帧 / 节奏走全局规则 / 气泡锚点在两个人头上；
##   2. 闲聊的编排：四句台词、说话人交替、锚点跟着说话人走；
##   3. 存档 → 任务面板的映射，以及开场引导在各档位下应该停在哪一档。
##
## ⚠️ **全程不写盘**：存档状态是往 autoload 的 SaveProgress **内存**里注入的假 config
##    （只 set _config / _loaded，从不调 mark_completed）。
##    这一点很重要——开发机上跑测试时用户常常正开着游戏，真实存档不能被碰。
##
## 跑法：<godot> --headless --path <项目> --script res://tools/test_eating_guests.gd

const TOWN_SCENE := "res://scenes/sideview/homeward_town.tscn"

var _checks := 0
var _failures := 0

var _save: SaveProgressService
var _quest_log: QuestLogService


## autoload 的 _ready 在 _initialize 阶段还没跑完（踩过），所以推迟到第一帧再开跑。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save = root.get_node_or_null("SaveProgress") as SaveProgressService
	_quest_log = root.get_node_or_null("QuestLog") as QuestLogService
	check(_save != null, "SaveProgress autoload 在位")
	check(_quest_log != null, "QuestLog autoload 在位")
	if _save == null or _quest_log == null:
		return _finish()

	await _check_guests()
	await _check_talk_lines()
	await _check_quest_panel()
	await _check_guide_stages()
	_finish()


# ---------------------------------------------------------------------------
# 1. 客人节点
# ---------------------------------------------------------------------------

func _check_guests() -> void:
	print("[1] 桌旁客人节点")
	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var guests := world.get_node_or_null("EatingGuests") as EatingGuestsNpc
	check(guests != null, "归航镇里存在 EatingGuests")
	if guests == null:
		town.queue_free()
		return

	check(guests.z_index == SideviewLayers.NPC_BACKDROP,
		"客人在背景路人层（%d），低于 NPC %d 与主角 %d" % [
			guests.z_index, SideviewLayers.NPC, SideviewLayers.PLAYER,
		])
	check(guests.scale.x < 1.0, "客人缩过（%.2f 倍）" % guests.scale.x)
	var sprite := guests.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var frames := sprite.sprite_frames
	check(frames.get_frame_count(&"idle") == 3, "三帧待机（%d）" % frames.get_frame_count(&"idle"))
	check(is_equal_approx(frames.get_animation_speed(&"idle"), TownNpcAnim.IDLE_FPS),
		"速度走全局规则 %.1f fps" % frames.get_animation_speed(&"idle"))
	check(frames.get_animation_loop(&"idle"), "待机是循环")

	# 两个人各自的气泡锚点：猫在左、狗在右，都在原点上方的头顶高度。
	var cat := guests.resolve_bubble_anchor(EatingGuestsNpc.Speaker.CAT)
	var dog := guests.resolve_bubble_anchor(EatingGuestsNpc.Speaker.DOG)
	print("      猫锚点 = (%.1f, %.1f)，狗锚点 = (%.1f, %.1f)" % [cat.x, cat.y, dog.x, dog.y])
	check(cat.x < dog.x, "猫的锚点在狗的左边")
	check(cat.y < guests.global_position.y and dog.y < guests.global_position.y,
		"两个锚点都在 NPC 原点之上（在头顶）")
	check(is_equal_approx(dog.x - cat.x, 89.5 * guests.scale.x),
		"两人锚点间距 = 帧内实测 89.5 × 缩放（%.1f）" % (dog.x - cat.x))
	# 缩放是挂在**节点**上的，所以锚点相对原点的高度也一起缩。
	# 这条同时是"脚底仍压在原点"的旁证：帧内头顶(22) 到内容底部(135) 是 113 个原尺寸像素，
	# 全程被缩放；最后那个 BUBBLE_GAP(6) 加在变换之外，**不参与缩放**。
	check(is_equal_approx(guests.global_position.y - cat.y, 113.0 * guests.scale.x + 6.0),
		"头顶锚点高度随缩放等比缩（%.1f）" % (guests.global_position.y - cat.y))
	check(guests.global_position.y < SideviewMapLayout.GROUND_BASELINE_Y,
		"客人脚底离开主街行走线，读作站得更靠后（%.0f < %.0f）" % [
			guests.global_position.y, SideviewMapLayout.GROUND_BASELINE_Y,
		])

	# 「背景板」的另一半：左缘必须留在麦大叔右侧，压到人物身上就穿帮了。
	# 位置本来就是拿 MAIDASHU_RIGHT_X 反推的，所以这里也拿同一个常量比 ——
	# 以后改缩放，这条不会跟着失效（这正是它比"写死一个坐标"值钱的地方）。
	var constants: Dictionary = town.get_script().get_script_constant_map()
	var maidashu := world.get_node_or_null("MaidaShu") as Node2D
	check(maidashu != null, "麦大叔在场景里")
	if maidashu != null:
		var maidashu_half: float = float(constants["MAIDASHU_RIGHT_X"]) - float(constants["MAIDASHU_X"])
		var maidashu_right := maidashu.global_position.x + maidashu_half
		var guest_left := guests.global_position.x - 85.5 * guests.scale.x
		check(guest_left > maidashu_right,
			"客人左缘留在麦大叔右缘之外（%.1f > %.1f）" % [guest_left, maidashu_right])

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 2. 闲聊台词与编排
# ---------------------------------------------------------------------------

func _check_talk_lines() -> void:
	print("[2] 闲聊的台词表")
	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame

	var guide := town.get("opening_guide") as OpeningGuide
	check(guide != null, "归航镇挂上了开场引导")
	if guide == null:
		town.queue_free()
		return

	var lines: Array = guide.get("eating_talk_lines")
	check(lines.size() == 4, "四句台词（%d）" % lines.size())
	var expected := [
		[EatingGuestsNpc.Speaker.CAT, "港口今天的雾是不是比昨天重？"],
		[EatingGuestsNpc.Speaker.DOG, "每年这个时候都有雾。"],
		[EatingGuestsNpc.Speaker.CAT, "……是吗？"],
		[EatingGuestsNpc.Speaker.DOG, "你别自己吓自己。"],
	]
	for index in mini(lines.size(), expected.size()):
		var line: Dictionary = lines[index]
		check(int(line["speaker"]) == int(expected[index][0]),
			"第 %d 句的说话人是 %s" % [index + 1, "猫" if int(expected[index][0]) == 0 else "狗"])
		check(String(line["text"]) == String(expected[index][1]),
			"第 %d 句台词一字未改" % [index + 1])

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 3. 存档 → 任务面板
# ---------------------------------------------------------------------------

func _check_quest_panel() -> void:
	print("[3] 存档 → 任务面板")
	var breakfast := SaveProgressService.TUTORIAL_BREAKFAST
	var first_sight := SaveProgressService.QUEST_FIRST_SIGHT_STEP

	# 空档：后续自由探索尚未解锁，只显示早饭和初见归航星。
	#
	# 攀爬（小孩的风筝）是「初见归航星」的第一个子任务，
	#    挂在那条任务下面当第一段落，**不是**第三条任务——这个从属关系是用户
	#    2026-09-22 亲口纠正的（「小孩的风筝就是初见归航星的第一个子任务」）。
	#    后面的「归航厅」在导航员对话后才解锁。
	_set_progress([])
	var view := _quest_log.get_track_view()
	check(String(view.get("section_title", "")) == "启程", "空档显示的小节是「启程」")
	var quests: Array = view.get("quests", [])
	check(quests.size() == 2, "对话前显示两条任务（%d）" % quests.size())
	if quests.size() == 2:
		check(String(quests[0]["title"]) == "麦大叔的早饭", "第一条是「麦大叔的早饭」")
		check(int(quests[0]["done_count"]) == 0 and int(quests[0]["total_count"]) == 3,
			"早饭 0/3（%d/%d）" % [int(quests[0]["done_count"]), int(quests[0]["total_count"])])
		check(String(quests[1]["title"]) == "初见归航星", "第二条是「初见归航星」")
		# 两步 = 攀爬 + 那个占位尾巴。爬到二楼算第一步。
		check(int(quests[1]["done_count"]) == 0 and int(quests[1]["total_count"]) == 4,
			"初见归航星 0/4（%d/%d）" % [int(quests[1]["done_count"]), int(quests[1]["total_count"])])
		check(String(quests[1]["current_text"]) == "顺着墙爬到二楼，帮小孩把风筝拿下来",
			"它的当前一步是第一个子任务：爬墙拿风筝（%s）" % String(quests[1]["current_text"]))
		# 第一段落的名字就是用户给这一段起的名字；「风筝」落在小结文案里。
		var segments: Array = quests[1]["segments"]
		check(segments.size() == 2, "初见归航星有两段（%d）" % segments.size())
		if segments.size() == 2:
			check(String(segments[0]["display_title"]) == "第一段落 · 认识攀爬",
				"第一段落叫「认识攀爬」（%s）" % String(segments[0]["display_title"]))

	# 教学全做完、闲聊也听完：**做完的「麦大叔的早饭」要整条消失**。
	# 用户 2026-09-22 的要求是"已经完成的就隐藏掉啊，不可以持久显示的"——
	# 所以这里验的是"不在列表里"，而不是"在列表里打了勾"。
	_set_progress([
		SaveProgressService.TUTORIAL_MOVE,
		SaveProgressService.TUTORIAL_JUMP,
		breakfast,
		SaveProgressService.STORY_EATING_TALK,
	])
	view = _quest_log.get_track_view()
	quests = view.get("quests", [])
	check(quests.size() == 1, "早饭做完后列表只剩「初见归航星」（%d）" % quests.size())
	var titles: Array = []
	for quest in quests:
		titles.append(String(quest["title"]))
		check(not quest.has("completed"),
			"面板数据里没有 completed 字段（「%s」）" % String(quest["title"]))
	check(not titles.has("麦大叔的早饭"),
		"做完的「麦大叔的早饭」已经不在列表里（%s）" % str(titles))
	if quests.size() == 1:
		check(String(quests[0]["title"]) == "初见归航星", "剩下的是「初见归航星」")
		check(String(quests[0]["current_text"]) == "顺着墙爬到二楼，帮小孩把风筝拿下来",
			"当前一步仍是爬墙（%s）" % String(quests[0]["current_text"]))

	# 爬完墙：任务的**下一个子任务**（占位尾巴）顶上来，整条任务仍然挂着。
	_set_progress([
		SaveProgressService.TUTORIAL_MOVE,
		SaveProgressService.TUTORIAL_JUMP,
		breakfast,
		SaveProgressService.STORY_EATING_TALK,
		SaveProgressService.QUEST_CHILD_KITE_PICKED,
		SaveProgressService.TUTORIAL_CLIMB,
	])
	view = _quest_log.get_track_view()
	quests = view.get("quests", [])
	check(quests.size() == 1, "爬完墙后当前任务仍在（%d 条）" % quests.size())
	if quests.size() == 1:
		check(int(quests[0]["done_count"]) == 2 and int(quests[0]["total_count"]) == 4,
			"初见归航星走到 2/4（%d/%d）" % [int(quests[0]["done_count"]), int(quests[0]["total_count"])])
		check(String(quests[0]["current_text"]) == "从正门进入归航厅",
			"当前一步是进入归航厅（%s）" % String(quests[0]["current_text"]))

	# 与导航员聊完 →「初见归航星」隐藏，后续自由探索任务出现。
	_set_progress([
		SaveProgressService.TUTORIAL_MOVE,
		SaveProgressService.TUTORIAL_JUMP,
		breakfast,
		SaveProgressService.STORY_EATING_TALK,
		SaveProgressService.QUEST_CHILD_KITE_PICKED,
		SaveProgressService.TUTORIAL_CLIMB,
		SaveProgressService.QUEST_ENTER_HALL,
		first_sight,
	])
	view = _quest_log.get_track_view()
	quests = view.get("quests", [])
	check(quests.size() == 1 and String(quests[0]["title"]) == "归航厅",
		"导航员对话后只剩自由探索任务")
	_set_progress([
		SaveProgressService.TUTORIAL_MOVE,
		SaveProgressService.TUTORIAL_JUMP,
		breakfast,
		SaveProgressService.STORY_EATING_TALK,
		SaveProgressService.QUEST_CHILD_KITE_PICKED,
		SaveProgressService.TUTORIAL_CLIMB,
		SaveProgressService.QUEST_ENTER_HALL,
		first_sight,
		SaveProgressService.QUEST_HALL_NEXT_STEP,
	])
	check(_quest_log.get_track_view().is_empty(), "后续任务也完成后面板收起")


# ---------------------------------------------------------------------------
# 4. 开场引导在各档位下停在哪一档
# ---------------------------------------------------------------------------

func _check_guide_stages() -> void:
	print("[4] 开场引导的档位")
	await _expect_stage([], OpeningGuide.Stage.MOVE_HINT, "空档 → 移动教学")
	await _expect_stage(
		[SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP],
		OpeningGuide.Stage.BREAKFAST_SHOUT,
		"只差早餐 → 直接演早餐吆喝"
	)
	var talk_town := await _expect_stage(
		[
			SaveProgressService.TUTORIAL_MOVE,
			SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST,
		],
		OpeningGuide.Stage.CHILD_CALL,
		"教学做完、没听过闲聊 → 闲聊与小孩引导并行"
	)
	if talk_town != null:
		var bubble := (talk_town.get("world_root") as Node2D).get_node_or_null("EatingGuestsBubble") as CharacterBubble
		check(bubble != null and bubble.visible, "闲聊第一句的气泡已经冒出来")
		talk_town.queue_free()
		await process_frame
	# 前面都做过、只剩攀爬那一段（而现在它没有写点，所以恒为"没完成"）：
	# 引导应该停在"等小孩开口"这一档，而不是直接收工。
	var child_town := await _expect_stage(
		[
			SaveProgressService.TUTORIAL_MOVE,
			SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST,
			SaveProgressService.STORY_EATING_TALK,
		],
		OpeningGuide.Stage.CHILD_CALL,
		"只剩小孩那一段 → 停在等小孩开口"
	)
	if child_town != null:
		# 出生点在世界 x 350，小孩在 1550 开外：这么远的距离不该触发喊话。
		var child_bubble := (child_town.get("world_root") as Node2D).get_node_or_null("WorldBubble")
		check(child_bubble == null or not (child_bubble as CharacterBubble).visible,
			"玩家还在出生点、离小孩很远，气泡不该冒出来")
		child_town.queue_free()
		await process_frame
	await _expect_stage(
		[
			SaveProgressService.TUTORIAL_MOVE,
			SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST,
			SaveProgressService.STORY_EATING_TALK,
			SaveProgressService.TUTORIAL_CLIMB,
		],
		OpeningGuide.Stage.DONE,
		"连攀爬都做过 → 不演任何东西"
	)


## 把存档设成 given，加载一次归航镇，等几帧，检查引导停在哪一档。返回那个场景（由调用方释放）。
func _expect_stage(completed: Array, expected: OpeningGuide.Stage, label: String) -> Node2D:
	_set_progress(completed)
	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	# 三帧：第一帧建场景、第二帧跑 _ready 里 call_deferred 开出来的那一步。
	await process_frame
	await process_frame
	await process_frame

	var guide := town.get("opening_guide") as OpeningGuide
	check(guide != null, "%s：引导在位" % label)
	if guide == null:
		town.queue_free()
		await process_frame
		return null
	check(guide.stage == expected,
		"%s（实际 stage = %d，期望 %d）" % [label, guide.stage, expected])
	# 小孩引导阶段还要检查场景内的气泡，所以把场景交回给调用方释放。
	if expected != OpeningGuide.Stage.CHILD_CALL:
		town.queue_free()
		await process_frame
		return null
	return town


# ---------------------------------------------------------------------------
# 帮手
# ---------------------------------------------------------------------------

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
