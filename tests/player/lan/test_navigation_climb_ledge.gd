extends SceneTree

## 「导航馆那面墙：扒边 → 往上爬 → 站上二楼」的**行为级**回归检查。
##
## 和 `test_navigation_climb_geometry.gd` 分工不同：那个查的是**几何本身**
## （墙 / 二楼面在哪、进了哪些组、meta 对不对），这个查的是**主角拿到这些几何之后的行为** ——
##   1. 跳上去能不能真的挂住，且挂的位置就在墙面上（不是在别的地方）；
##   2. 往上爬的位移是不是每帧连续的（不是 12 Hz 一跳的"抖"）；
##   3. 爬完是不是站在二楼面上，并且能在那上面走；
##   4. 两个墙面（左 / 右）表现对称；按 S 能主动放手掉下去。
##
## 🔴 **这个文件存在的头号理由**（踩过一次，2026-09-22）：
##    主角扒边时被 `wall.global_position.x` 喂了一次 → "抓住墙"变成了"被瞬移到 945 px 以外的
##    另一个地方"，表现是主角乱飞、抓不住墙、爬完摔回地面，镜头跟着他整屏乱跳。
##
## ⚠️ 而且要命的是：**这个 bug 在出生点附近不发作**。world_root.position.x == 0 时
##    「全局坐标」与「父节点局部坐标」恰好相等。所以下面每个场景都 （a）先把主角挪到镇子中段、
##    （b）在断言的那一刻显式检查"镜头确实已经滚过" —— 少了 (b)，测试会在 bug 存在时依然全绿。
##
## ⚠️ **全程不写盘**：存档是往 autoload 的 SaveProgress **内存**里注入的假 config。
##
## 跑法：homeing-star-test/run-tests.ps1 -Test test_navigation_climb_ledge

const TOWN_SCENE := "res://scenes/sideview/homeward_town.tscn"

## 位移连续性阈值。攀爬全程 (39, -80) px 分 8 个动画帧走完，物理 60 fps / 动画 12 fps
## → 每物理帧的正常步长约 1.0 px（x）/ 2.0 px（y）。
## 出问题的版本是 5.6 / 11.4 px 一跳。阈值取在两者之间，既不误报也不会漏。
const MAX_STEP_X := 4.0
const MAX_STEP_Y := 6.0

## 挂住之后允许的位置误差（px）。物理步进 + 碰撞解算会有零点几像素的余量。
const HANG_TOLERANCE := 1.5

var _checks := 0
var _failures := 0

var _save: SaveProgressService


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save = root.get_node_or_null("SaveProgress") as SaveProgressService
	check(_save != null, "SaveProgress autoload 在位")
	if _save == null:
		return _finish()

	# 「开场整段都做过了」：引导不会演任何东西，也就不会有人冻住输入、弹气泡干扰走位。
	# 同时 opening_area_active 保持 false → 能力全开，跳 / 二段跳都能用。
	_set_progress([
		SaveProgressService.TUTORIAL_MOVE,
		SaveProgressService.TUTORIAL_JUMP,
		SaveProgressService.TUTORIAL_BREAKFAST,
		SaveProgressService.STORY_EATING_TALK,
		SaveProgressService.TUTORIAL_CLIMB,
	])

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var player := town.get("player") as Node2D
	var world := town.get("world_root") as Node2D
	var geometry := world.get_node_or_null("NavigationClimbGeometry")
	# ⚠️ 二楼面是 geometry 的**子节点**（geometry.add_child(second_floor)），
	#    不是 world_root 的直接子节点 —— 别在 world_root 底下找它。
	var second_floor := geometry.get_node_or_null("SecondFloorSurface") as Node2D
	check(player != null and world != null and geometry != null,
		"归航镇里主角 / world_root / NavigationClimbGeometry 都在位")
	if player == null or world == null or geometry == null:
		town.queue_free()
		return _finish()

	var left_x := float(geometry.get_meta(&"left_x"))
	var right_x := float(geometry.get_meta(&"right_x"))
	var floor_y := float(geometry.get_meta(&"second_floor_y"))
	var standoff := float(_constants(player)["LEDGE_WALL_STANDOFF"])
	var hang_feet_offset := float(_constants(player)["LEDGE_HANG_FEET_OFFSET_Y"])
	var states := _air_states(player)
	print("参考值：左墙 %.2f / 右墙 %.2f / 二楼 y %.2f / 悬挂偏移 %.1f / 站开 %.1f" % [
		left_x, right_x, floor_y, hang_feet_offset, standoff,
	])

	# 二楼面必须是「有限宽可站立面」，否则爬上去也站不住。
	check(second_floor != null and second_floor.is_in_group(&"second_floor_surface"),
		"二楼面节点在 second_floor_surface 组里")

	await _scenario_grab_and_climb(
		player, world, "左墙（从建筑左侧往右跳上去）",
		left_x - 70.0, 1.0, left_x, left_x, right_x,
		standoff, hang_feet_offset, floor_y, states
	)
	await _scenario_grab_and_climb(
		player, world, "右墙（从建筑右侧往左跳上去）",
		right_x + 130.0, -1.0, right_x, left_x, right_x,
		standoff, hang_feet_offset, floor_y, states
	)
	await _scenario_drop_from_ledge(
		player, world, left_x, standoff, hang_feet_offset, floor_y, states
	)
	await _scenario_walk_on_second_floor(player, floor_y, left_x, right_x)

	town.queue_free()
	await process_frame
	_finish()


# ---------------------------------------------------------------------------
# 1. 跳上去 → 挂住 → 往上爬 → 站上二楼
# ---------------------------------------------------------------------------

func _scenario_grab_and_climb(
	player: Node2D, world: Node2D, label: String,
	start_x: float, direction: float, wall_x: float, left_x: float, right_x: float,
	standoff: float, hang_feet_offset: float, floor_y: float, states: Dictionary
) -> void:
	print("")
	print("=== %s ===" % label)
	_place_player(player, start_x)

	var action := &"ui_right" if direction > 0.0 else &"ui_left"
	Input.action_press(action)

	var jump_hold := 0
	var double_jump_done := false
	var climb_requested := false
	var hang_position := Vector2.INF
	var scroll_at_grab := 0.0
	var climb_samples: Array[Vector2] = []
	var final_position := Vector2.INF
	var max_step := Vector2.ZERO
	var last_climb := Vector2.INF

	for i in 400:
		var state := int(player.get("air_state"))
		var pos: Vector2 = player.get("position")
		var velocity: Vector2 = player.get("velocity")

		if i == 3:
			jump_hold = 2
		elif not double_jump_done \
				and state == int(states["RISING"]) and velocity.y > -60.0:
			# 升到接近顶点再补二段跳：一段跳最高 103 px，够不着二楼（要 158 px 以上）。
			double_jump_done = true
			jump_hold = 2
		elif not climb_requested and state == int(states["LEDGE_HANGING"]):
			climb_requested = true
			jump_hold = 2

		if jump_hold > 0:
			Input.action_press(&"jump")
			jump_hold -= 1
			if jump_hold == 0:
				Input.action_release(&"jump")

		if hang_position == Vector2.INF and state >= int(states["LEDGE_GRABBING"]):
			hang_position = pos
			scroll_at_grab = world.position.x
		if state == int(states["LEDGE_CLIMBING"]):
			if last_climb != Vector2.INF:
				max_step.x = maxf(max_step.x, absf(pos.x - last_climb.x))
				max_step.y = maxf(max_step.y, absf(pos.y - last_climb.y))
			last_climb = pos
			climb_samples.append(pos)
		if state == int(states["GROUNDED"]) and pos.y < floor_y + 40.0:
			final_position = pos
			break

		await physics_frame

	Input.action_release(action)
	var scroll_after := world.position.x

	# ① 先证明这一场跑在「镜头已经滚过」的条件下 —— 否则全局 / 局部坐标恰好相等，什么都查不出来。
	check(absf(scroll_at_grab) > 500.0,
		"%s：挂住时镜头已滚过（scroll = %.1f，远离 0 才有诊断力）" % [label, scroll_at_grab])

	check(hang_position != Vector2.INF, "%s：真的挂住了（状态走到了 LEDGE_*）" % label)
	if hang_position == Vector2.INF:
		print("      ✗ 一次都没挂住，后面的位置断言没有意义，直接跳过")
		return

	var expected_hang_x := wall_x - direction * standoff
	var expected_hang_y := floor_y + hang_feet_offset
	print("      挂住位置 = (%.2f, %.2f)，期望 (%.2f, %.2f)，镜头 scroll = %.1f" % [
		hang_position.x, hang_position.y, expected_hang_x, expected_hang_y, scroll_at_grab])
	# ② 核心回归断言：挂住的位置必须就在**这面墙**上。
	check(absf(hang_position.x - expected_hang_x) <= HANG_TOLERANCE,
		"%s：挂住的 x 就在墙面上（偏差 %.2f px ≤ %.1f）" % [
			label, absf(hang_position.x - expected_hang_x), HANG_TOLERANCE])
	check(absf(hang_position.y - expected_hang_y) <= HANG_TOLERANCE,
		"%s：挂住的 y = 二楼 + 悬挂偏移（偏差 %.2f px）" % [
			label, absf(hang_position.y - expected_hang_y)])
	# 挂点在墙的**外侧**（玩家是从外面跳上来抓住的），别爬成镜像。
	check(signf(hang_position.x - wall_x) == -direction,
		"%s：挂点在墙的外侧（挂 %.2f / 墙 %.2f，方向 %.0f）" % [
			label, hang_position.x, wall_x, direction])

	# ③ 爬的位移必须每帧连续。出问题的版本是"每 5 个物理帧跳一次"。
	check(climb_samples.size() >= 20,
		"%s：攀爬动作铺开了 %d 帧（≥20 才说明是逐帧推进）" % [label, climb_samples.size()])
	check(max_step.x <= MAX_STEP_X and max_step.y <= MAX_STEP_Y,
		"%s：攀爬位移每帧连续（最大步长 %.2f / %.2f px，上限 %.1f / %.1f）" % [
			label, max_step.x, max_step.y, MAX_STEP_X, MAX_STEP_Y])

	# ④ 往上爬 = y 单调减小（不能在半路上下抖）。
	var backwards := 0
	for index in range(1, climb_samples.size()):
		if climb_samples[index].y > climb_samples[index - 1].y + 0.01:
			backwards += 1
	check(backwards == 0, "%s：爬升过程 y 单调向上（回退帧数 %d）" % [label, backwards])

	# ⑤ 终点：站在二楼面上，而且是在这栋楼的横向范围里、在墙的**内侧**。
	check(final_position != Vector2.INF, "%s：最后回到了 GROUNDED 状态" % label)
	if final_position != Vector2.INF:
		print("      终点 = (%.2f, %.2f)" % [final_position.x, final_position.y])
		check(absf(final_position.y - floor_y) <= HANG_TOLERANCE,
			"%s：站在二楼高度上（y = %.2f，二楼 %.2f）" % [label, final_position.y, floor_y])
		check(signf(final_position.x - wall_x) == direction,
			"%s：终点翻到了墙的内侧（终点 %.2f / 墙 %.2f）" % [label, final_position.x, wall_x])
		check(final_position.x > left_x - HANG_TOLERANCE and final_position.x < right_x + HANG_TOLERANCE,
			"%s：终点落在二楼面的横向范围里（%.2f 在 %.2f .. %.2f 内）" % [
				label, final_position.x, left_x, right_x])
	check(absf(scroll_after) > 500.0, "%s：全程镜头都在中段（没有被瞬移带回镇口）" % label)


# ---------------------------------------------------------------------------
# 2. 按 S 主动放手
# ---------------------------------------------------------------------------

func _scenario_drop_from_ledge(
	player: Node2D, world: Node2D, wall_x: float,
	standoff: float, hang_feet_offset: float, floor_y: float, states: Dictionary
) -> void:
	print("")
	print("=== 挂在墙上按 S：应该放开手、掉回主街 ===")
	_place_player(player, wall_x - 70.0)
	# 直接把人放到"已经挂住"的坐标上再走一帧，比重新演一遍跳上去省事，
	# 而且测的是同一件事（放手逻辑只看 air_state）。
	player.set("position", Vector2(wall_x - standoff, floor_y + hang_feet_offset))
	Input.action_press(&"ui_right")
	await physics_frame
	await physics_frame
	Input.action_release(&"ui_right")

	# 先确认他确实处理"挂在墙上"的状态，否则这个场景什么都没验到。
	var state := int(player.get("air_state"))
	if state < int(states["LEDGE_GRABBING"]) or state > int(states["LEDGE_CLIMBING"]):
		check(false, "放手场景：前置状态是挂墙（实际 %d）" % state)
		return
	check(true, "放手场景：前置状态是挂墙")

	# ⚠️ 必须等挂住的**开场动画播完**再按 S：S 只在 LEDGE_HANGING 这一档才被读取
	#    （LEDGE_GRABBING 是"抓住"那 6 帧，按什么都没用）。过早按键会得到
	#    "按了 S 却还挂在那儿"的假失败——我第一版就是这么写错的。
	var settled := false
	for i in 120:
		await physics_frame
		if int(player.get("air_state")) == int(states["LEDGE_HANGING"]):
			settled = true
			break
	check(settled, "放手场景：挂住的动画播完，进入可以操作的 LEDGE_HANGING")

	Input.action_press(&"ui_down")
	# 按住两三帧足够被读到（drop_from_ledge 当帧就把状态改成 FALLING）。
	for i in 3:
		await physics_frame
	Input.action_release(&"ui_down")

	var left_wall := false
	var reached_street := false
	for i in 240:
		await physics_frame
		var current := int(player.get("air_state"))
		var pos: Vector2 = player.get("position")
		if current < int(states["LEDGE_GRABBING"]):
			left_wall = true
		if left_wall and pos.y >= floor_y + 200.0:
			reached_street = true
			break
	check(left_wall, "按 S 之后脱离了挂墙状态")
	check(reached_street, "一路掉回主街（y 越过二楼 +200）")


# ---------------------------------------------------------------------------
# 3. 二楼面上能走路
# ---------------------------------------------------------------------------

func _scenario_walk_on_second_floor(
	player: Node2D, floor_y: float, left_x: float, right_x: float
) -> void:
	print("")
	print("=== 二楼面上能左右走 ===")
	_place_player(player, left_x + 40.0, floor_y)
	var start_x: float = player.get("position").x

	Input.action_press(&"ui_right")
	var stayed_on_floor := true
	var highest_drop := 0.0
	for i in 60:
		await physics_frame
		var pos: Vector2 = player.get("position")
		if int(player.get("air_state")) == 0:
			highest_drop = maxf(highest_drop, absf(pos.y - floor_y))
		else:
			stayed_on_floor = false
	Input.action_release(&"ui_right")

	var end_x: float = player.get("position").x
	print("      从 x = %.1f 走到 %.1f（二楼 %.1f .. %.1f）" % [start_x, end_x, left_x, right_x])
	check(end_x > start_x + 20.0, "在二楼面上真的走动了（位移 %.1f px）" % (end_x - start_x))
	check(stayed_on_floor, "全程没有掉出二楼面（脱离 GROUNDED 的次数 = 0）")
	check(highest_drop <= HANG_TOLERANCE, "走动时高度钉在二楼面（最大偏移 %.2f px）" % highest_drop)


# ---------------------------------------------------------------------------
# 帮手
# ---------------------------------------------------------------------------

## 把主角放到确定的起点：位置 / 速度 / 落地状态都重置，免得上一场留下的惯性干扰。
func _place_player(player: Node2D, x: float, y: float = 555.0) -> void:
	player.set("position", Vector2(x, y))
	player.set("velocity", Vector2.ZERO)
	player.set("air_state", int(_air_states(player)["GROUNDED"]))


## 主角脚本里的常量表（AirState 枚举、悬挂偏移、站开距离都从这儿取，不写死数字）。
func _constants(player: Node2D) -> Dictionary:
	return player.get_script().get_script_constant_map()


func _air_states(player: Node2D) -> Dictionary:
	return _constants(player)["AirState"]


## 往 autoload 的内存里塞一份假的存档内容（**磁盘上的 progress.cfg 一个字节都不会动**）。
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
