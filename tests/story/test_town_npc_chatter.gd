extends SceneTree

## 「城镇 NPC 日常闲聊」的代码级回归检查（town_npc_chatter.gd）。
##
## 用户 2026-09-22 的设定：跟 NPC 做完任务之后，他不再是块木头 ——
## 以后每次经过都会从固定话术里随机说一句。第一批是麦大叔（早饭）和第三栋房子那个小孩（攀爬）。
##
## 覆盖五件事：
##   1. 接线：闲聊系统在镇里，两个人物都登记了，门槛 id 分别是 breakfast / climb；
##   2. **门槛关着时它一个字都不说**（那时候 NPC 的话归开场引导管）；
##   3. 门槛开了：走进圈里说一句 → 站在跟前不再刷屏 → 退远了再走回来又说一句（迟滞）；
##   4. 随机：**同一人物绝不连着说同一句**（这是硬保证，不是概率）；
##   5. 气泡是全城**共用同一个实例**（和开场引导抢同一块屏幕会叠成一团）。
##
## ⚠️ **全程不写盘**：存档状态是往 autoload 的 SaveProgress **内存**里注入的假 config
##    （只 set _config / _loaded，从不调 mark_completed）。开发机上跑测试时用户常常正开着游戏，
##    真实存档不能被碰。
##
## 跑法：homeing-star-test/run-tests.ps1 -Test test_town_npc_chatter

const TOWN_SCENE := "res://scenes/levels/town/homeward_town.tscn"

## 判断"没说过话"用的哨兵值：档案里的 `last` 初始就是它。
const NEVER_SPOKEN := -1

## 用户 2026-09-22 23:29 给的麦大叔话术**原文**，一字未改地抄在这里当对照。
##
## ⚠️ **这是故意抄第二份的**：台词表在 town_npc_chatter.gd 里，这里再列一遍，
## 谁改坏了（删句 / 改字 / 把"岚！"开头统一化）测试立刻报出来。
## 抄的是"用户说过的话"，不是"代码里现在写的东西"——所以**改台词先改这里**，
## 否则这条测试就退化成"自己验证自己"、什么也守不住。
const USER_MAIDASHU_LINES := [
	"岚！慢点跑，撞翻我的锅你可得赔！",
	"岚！今天肉饼烤得不错，给你留着呢！",
	"又往外跑？鞋带系紧点！",
	"岚！吃饭没有？",
	"喂！听见没有？吃——饭——！",
	"今天不赊账啊！……算了，你除外。",
	"刚才那桌客人吃了三个肉饼，你可不能输。",
	"岚。回来的时候记得来一趟。",
	"不管去哪儿，肚子别空着。",
]

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

	await _check_wiring()
	await _check_gate_closed()
	await _check_ambient_flow()
	await _check_randomness()
	await _check_shared_bubble()
	_finish()


# ---------------------------------------------------------------------------
# 1. 接线
# ---------------------------------------------------------------------------

func _check_wiring() -> void:
	print("[1] 接线")
	_set_progress(_state_after_climb())

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var chatter := town.get("npc_chatter") as TownNpcChatter
	check(chatter != null, "归航镇挂上了 NpcChatter")
	if chatter == null or world == null:
		town.queue_free()
		await process_frame
		return

	var maidashu := world.get_node_or_null("MaidaShu") as MaidaShuNpc
	var child := world.get_node_or_null("ChildNpc") as ChildNpc
	check(maidashu != null and child != null, "麦大叔与小孩都在位")

	var maidashu_profile := chatter.get_profile(maidashu)
	var child_profile := chatter.get_profile(child)
	check(not maidashu_profile.is_empty(), "麦大叔登记进了闲聊系统")
	check(not child_profile.is_empty(), "小孩登记进了闲聊系统")
	if not maidashu_profile.is_empty():
		check(maidashu_profile["gate"] == SaveProgressService.TUTORIAL_BREAKFAST,
			"麦大叔的门槛是早饭（%s）" % String(maidashu_profile["gate"]))
		check((maidashu_profile["lines"] as Array).size() == TownNpcChatter.MAIDASHU_AMBIENT_LINES.size(),
			"他的台词表就是常量表（%d 句）" % (maidashu_profile["lines"] as Array).size())
		check(int(maidashu_profile["last"]) == NEVER_SPOKEN, "上电时他还没说过话")
	if not child_profile.is_empty():
		check(child_profile["gate"] == SaveProgressService.TUTORIAL_CLIMB,
			"小孩的门槛是攀爬（%s）" % String(child_profile["gate"]))

	check(TownNpcChatter.CHATTER_REARM_RANGE > TownNpcChatter.CHATTER_RANGE,
		"迟滞距离必须大于触发距离（%.0f > %.0f）" % [
			TownNpcChatter.CHATTER_REARM_RANGE, TownNpcChatter.CHATTER_RANGE,
		])
	check(TownNpcChatter.CHATTER_DURATION > 0.0, "气泡停留时长是正数")

	# 台词表本身：**用户给的原文必须一条不少地在里面**，且表内不重复
	# （重复会让"不连着说同一句"看起来失效）。
	#
	# ⚠️ 这里钉的是**整份文案**，不是抽查一句：用户 2026-09-22 23:29 给的是成品，
	# 日后有人改台词时若顺手删掉某句、或把"岚！"开头统一化，这几条会立刻报出来。
	for line: String in USER_MAIDASHU_LINES:
		check(TownNpcChatter.MAIDASHU_AMBIENT_LINES.has(line),
			"麦大叔的台词里有用户那句「%s」" % line)
	check(TownNpcChatter.MAIDASHU_AMBIENT_LINES.size() == USER_MAIDASHU_LINES.size(),
		"麦大叔的台词表就是用户给的那九条（实际 %d 条）" % TownNpcChatter.MAIDASHU_AMBIENT_LINES.size())
	check(TownNpcChatter.CHILD_AMBIENT_LINES.has("岚，带我去冒险好不好？"),
		"小孩的台词里有用户给的那句「岚，带我去冒险好不好？」")
	check(_has_no_duplicate(TownNpcChatter.MAIDASHU_AMBIENT_LINES), "麦大叔的台词表里没有重复句")
	check(_has_no_duplicate(TownNpcChatter.CHILD_AMBIENT_LINES), "小孩的台词表里没有重复句")

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 2. 门槛关着：一个字都不说
# ---------------------------------------------------------------------------

func _check_gate_closed() -> void:
	print("[2] 门槛关着时不出声")
	# 只学过移动和跳跃：麦大叔的早饭还没吃，小孩那面墙更没爬。
	_set_progress([SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP])

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var chatter := town.get("npc_chatter") as TownNpcChatter
	var player := town.get("player") as Node2D
	var maidashu := world.get_node_or_null("MaidaShu") as MaidaShuNpc
	var child := world.get_node_or_null("ChildNpc") as ChildNpc
	check(chatter != null and maidashu != null and child != null and player != null,
		"闲聊系统与两位人物都在位")
	if chatter == null or maidashu == null or child == null or player == null:
		town.queue_free()
		await process_frame
		return
	var maidashu_profile := chatter.get_profile(maidashu)
	var child_profile := chatter.get_profile(child)
	check(not maidashu_profile.is_empty() and not child_profile.is_empty(),
		"两位人物都登记进了闲聊系统")
	if maidashu_profile.is_empty() or child_profile.is_empty():
		town.queue_free()
		await process_frame
		return

	# 走到麦大叔跟前。
	player.position.x = maidashu.position.x
	await process_frame
	await process_frame
	check(int(maidashu_profile["last"]) == NEVER_SPOKEN,
		"早饭没做完 → 走到麦大叔跟前他也不闲聊（他的话归引导管）")
	check(bool(maidashu_profile["inside"]),
		"这一趟照样烧掉（进圈就置位）—— 他站在旁边不动时不该突然开始刷屏")

	# ⚠️ 走到小孩跟前之前**先把气泡让出来**。不这么做的话这两条断言会互相掩护：
	# 麦大叔万一说了话，气泡要占 2.6 秒，小孩就"因为气泡被占着"而闭嘴 ——
	# 断言照样通过，但它验的已经不是门槛了。这种"因为别的原因恰好通过"必须掐掉。
	chatter.call(&"_hide_bubble")

	# 走到小孩跟前。
	player.position.x = child.position.x
	await process_frame
	await process_frame
	check(int(child_profile["last"]) == NEVER_SPOKEN,
		"攀爬没做完 → 走到小孩跟前他也不闲聊")
	# 这一档下引导还在演早饭那段，小孩那句话轮不到；这里只断言"闲聊系统没抢着说"。
	var bubble := world.get_node_or_null("WorldBubble") as CharacterBubble
	if bubble != null and bubble.visible:
		var label := bubble.get_node_or_null("BubblePanel/BubbleText") as Label
		var text := label.text if label != null else ""
		check(not TownNpcChatter.CHILD_AMBIENT_LINES.has(text),
			"屏幕上就算有气泡，也不是闲聊系统那句（%s）" % text)

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 3. 门槛开了：经过说一句 + 迟滞
# ---------------------------------------------------------------------------

func _check_ambient_flow() -> void:
	print("[3] 引导做完之后：经过说一句 + 迟滞")
	# 全做完了 → 开场引导直接 DONE，不会来抢气泡（这样这一段验的就纯粹是闲聊系统）。
	_set_progress(_state_after_climb())

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var guide := town.get("opening_guide") as OpeningGuide
	var chatter := town.get("npc_chatter") as TownNpcChatter
	var player := town.get("player") as Node2D
	var maidashu := world.get_node_or_null("MaidaShu") as MaidaShuNpc
	check(guide != null and chatter != null and maidashu != null and player != null,
		"引导 / 闲聊系统 / 麦大叔 / 主角都在位")
	if guide == null or chatter == null or maidashu == null or player == null:
		town.queue_free()
		await process_frame
		return

	check(guide.stage == OpeningGuide.Stage.DONE,
		"整段开场都走过 → 引导收工，不会来抢气泡（实际 %d）" % guide.stage)

	var bubble := world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble == null or not bubble.visible, "玩家还在出生点（离麦大叔 600+ px），没有气泡")

	# ① 走进圈里 → 说一句。
	player.position.x = maidashu.position.x
	await process_frame
	await process_frame

	bubble = world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble != null and bubble.visible, "走到麦大叔跟前，他开口了")
	var first_line := ""
	if bubble != null and bubble.visible:
		var label := bubble.get_node_or_null("BubblePanel/BubbleText") as Label
		first_line = label.text if label != null else ""
		check(TownNpcChatter.MAIDASHU_AMBIENT_LINES.has(first_line),
			"说的那句在他的话术表里（%s）" % first_line)

		# 气泡位置的三条回归线，照抄 test_child_npc：只验 visible / 文字是抓不到坐标 bug 的
		# （气泡挂在 world_root 下、锚点是世界坐标，偏掉的就是整个滚动量）。
		var anchor := maidashu.resolve_bubble_anchor()
		check(bubble.global_position.distance_to(anchor) < 1.0,
			"气泡尾巴落在麦大叔头顶锚点上（偏 %.1f px）" % bubble.global_position.distance_to(anchor))
		var screen := root.get_visible_rect()
		var panel := bubble.get_node_or_null("BubblePanel") as Control
		check(screen.has_point(anchor), "锚点落在画面内（%.1f, %.1f）" % [anchor.x, anchor.y])
		if panel != null:
			check(screen.encloses(panel.get_global_rect()),
				"整块气泡底板都在画面内（%s）" % panel.get_global_rect())

	# ② 他挂一会儿会自己收掉。
	await create_timer(TownNpcChatter.CHATTER_DURATION + 0.4).timeout
	bubble = world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble != null and not bubble.visible,
		"气泡到点自己收掉了（%.1f 秒）" % TownNpcChatter.CHATTER_DURATION)

	# ③ 站在跟前不动 → **不再说**（用户要的是"每次经过"，不是"站旁边刷屏"）。
	var maidashu_profile := chatter.get_profile(maidashu)
	var spoken_once := int(maidashu_profile["last"])
	check(spoken_once >= 0, "确实说过一次（第 %d 句）" % spoken_once)
	# 在圈内轻微挪一下，绝不能触发新的一句。
	player.position.x = maidashu.position.x + TownNpcChatter.CHATTER_RANGE - 10.0
	await process_frame
	await process_frame
	bubble = world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble == null or not bubble.visible, "还在圈里挪来挪去 → 没有再开口")
	check(int(maidashu_profile["last"]) == spoken_once, "上一句的记录没被改（没有悄悄重说）")

	# ④ 退到迟滞距离之外 → 再走回来 → 又说一句，而且**换了一句**。
	player.position.x = maidashu.position.x + TownNpcChatter.CHATTER_REARM_RANGE + 20.0
	await process_frame
	await process_frame
	check(not bool(maidashu_profile["inside"]), "退出迟滞距离 → 这一趟复位，可以再说")
	player.position.x = maidashu.position.x
	await process_frame
	await process_frame
	bubble = world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble != null and bubble.visible, "再走回来 → 又开口了")
	if bubble != null and bubble.visible:
		var label := bubble.get_node_or_null("BubblePanel/BubbleText") as Label
		var second_line := label.text if label != null else ""
		check(TownNpcChatter.MAIDASHU_AMBIENT_LINES.has(second_line),
			"第二句也在话术表里（%s）" % second_line)
		check(second_line != first_line,
			"不会连着说同一句（%s ≠ %s）" % [second_line, first_line])

	# ⑤ 小孩也一样：先退开（他现在会换一句），走到他那条街上。
	chatter.call(&"_hide_bubble")
	player.position.x = child_x(world) + TownNpcChatter.CHATTER_REARM_RANGE + 20.0
	await process_frame
	await process_frame
	player.position.x = child_x(world)
	await process_frame
	await process_frame
	bubble = world.get_node_or_null("WorldBubble") as CharacterBubble
	check(bubble != null and bubble.visible, "走到小孩跟前，他也开口了")
	if bubble != null and bubble.visible:
		var label := bubble.get_node_or_null("BubblePanel/BubbleText") as Label
		var child_line := label.text if label != null else ""
		check(TownNpcChatter.CHILD_AMBIENT_LINES.has(child_line),
			"小孩说的是他自己的话术（%s）" % child_line)
		# 别串台：麦大叔的台词绝不能出现在小孩头上。
		check(not TownNpcChatter.MAIDASHU_AMBIENT_LINES.has(child_line),
			"没有把麦大叔的台词挂到小孩头上")

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 4. 随机：不连着说同一句
# ---------------------------------------------------------------------------

func _check_randomness() -> void:
	print("[4] 随机与「不连着重复」")
	_set_progress(_state_after_climb())

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var chatter := town.get("npc_chatter") as TownNpcChatter
	var world := town.get("world_root") as Node2D
	var maidashu := world.get_node_or_null("MaidaShu") as MaidaShuNpc
	check(chatter != null and maidashu != null, "闲聊系统与麦大叔在位")
	if chatter == null or maidashu == null:
		town.queue_free()
		await process_frame
		return
	var profile := chatter.get_profile(maidashu)
	check(not profile.is_empty(), "拿到了麦大叔的闲聊档案")
	if profile.is_empty():
		town.queue_free()
		await process_frame
		return

	# 直接连抽 60 次：比"反复走来走去"更狠，也更快。
	var seen: Dictionary = {}
	var repeats := 0
	var previous := ""
	var outside := 0
	for i in 60:
		var line := String(chatter.call(&"_pick_line", profile))
		if not TownNpcChatter.MAIDASHU_AMBIENT_LINES.has(line):
			outside += 1
		if line == previous:
			repeats += 1
		seen[line] = true
		previous = line

	check(outside == 0, "60 次抽出来的每一句都在话术表里（越界 %d 次）" % outside)
	check(repeats == 0, "60 次连抽里没有一次和上一句相同（实际 %d 次）" % repeats)
	check(seen.size() >= 2, "抽到的不止一种话（%d 种）" % seen.size())
	print("      60 次抽到 %d 种：%s" % [seen.size(), str(seen.keys())])
	# 上一句的位置也要跟着更新，否则"不重复"这条下一轮就失效了。
	check(int(profile["last"]) >= 0, "档案里记着上一句是第几句（%d）" % int(profile["last"]))

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 5. 共用气泡
# ---------------------------------------------------------------------------

func _check_shared_bubble() -> void:
	print("[5] 气泡共用同一个实例")
	_set_progress(_state_after_climb())

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var guide := town.get("opening_guide") as OpeningGuide
	var chatter := town.get("npc_chatter") as TownNpcChatter
	var player := town.get("player") as Node2D
	var child := world.get_node_or_null("ChildNpc") as ChildNpc
	check(guide != null and chatter != null and child != null and player != null,
		"引导 / 闲聊系统 / 小孩 / 主角都在位")
	if guide == null or chatter == null or child == null or player == null:
		town.queue_free()
		await process_frame
		return

	# 先让开场引导把它的气泡建出来（正常流程里它在吆喝那一刻建）。
	guide.call(&"_ensure_bubble")
	var guide_bubble := guide.get("_bubble") as CharacterBubble
	check(guide_bubble != null, "开场引导拿到了气泡")

	# 再让闲聊系统说话 —— 它必须捡到**同一个**实例，而不是自己再建一个。
	chatter.call(&"_hide_bubble")
	player.position.x = child.position.x
	await process_frame
	await process_frame

	var chatter_bubble := chatter.get("_bubble") as CharacterBubble
	check(chatter_bubble != null and chatter_bubble.visible, "闲聊系统也开口了")
	check(chatter_bubble == guide_bubble,
		"两边拿到的是同一个气泡实例（不然屏幕上会同时叠两块）")

	# ⚠️ 用 contains 而不是 == ：Godot 撞名时会把后来那个改名成 `@WorldBubble@2`，
	# 死认原名的话"自己又建了一个"这个错误正好会漏过去。
	var named := 0
	for node in world.get_children():
		if String(node.name).contains(String(CharacterBubble.BUBBLE_NODE_NAME)):
			named += 1
	check(named == 1, "world_root 底下喊话气泡只有一块（实际 %d 块）" % named)

	town.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 帮手
# ---------------------------------------------------------------------------

## 「前面全做过、连攀爬也做完了」这一档：两个闲聊门槛都开着，而引导已经收工。
func _state_after_climb() -> Array:
	return [
		SaveProgressService.TUTORIAL_MOVE,
		SaveProgressService.TUTORIAL_JUMP,
		SaveProgressService.TUTORIAL_BREAKFAST,
		SaveProgressService.STORY_EATING_TALK,
		SaveProgressService.TUTORIAL_CLIMB,
	]


func child_x(world: Node2D) -> float:
	var child := world.get_node_or_null("ChildNpc") as ChildNpc
	return child.position.x if child != null else 0.0


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


func _has_no_duplicate(lines: Array) -> bool:
	for line in lines:
		if lines.count(line) > 1:
			return false
	return true


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
