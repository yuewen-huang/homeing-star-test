extends SceneTree

## 镜湖（12 屏）的数值关系 + 阴阳切换（状态 / 冷却 / 黑白互换且几何不变 / 操作颠倒）：世界宽 / 分区 / 美术尺寸 / 水线 / 视差 / 镜头夹取 / BOSS 区镜头余量 / 出生点 / 层号 / 脚下接触阴影。
## 好不好看仍然由人开游戏看，这里只管"贴图和代码对得上"。
##
## 用法：homeing-star-test/run-tests.ps1 -Test test_mirror_lake

const SCENE_PATH := "res://scenes/levels/mirror_lake/mirror_lake.tscn"

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


## 贴图宽的公式（美术管线用同一个）：ceil((1280 + (W-1280) × ratio) / 32) × 32
func expected_layer_width(ratio: float) -> int:
	return int(ceilf((MirrorLake.VIEW_WIDTH + (MirrorLake.WORLD_LENGTH - MirrorLake.VIEW_WIDTH) * ratio) / 32.0)) * 32


func run() -> void:
	_check_constants()
	_check_zones()
	_check_boss_camera()
	await _check_scene()
	_check_switch_constants()
	await _check_switch_state()
	await _check_celestials()
	await _check_switch_input()
	print("")
	print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_constants() -> void:
	check(MirrorLake.WORLD_LENGTH == 15360.0, "世界宽 15360")
	check(is_equal_approx(MirrorLake.WORLD_LENGTH / MirrorLake.VIEW_WIDTH, 12.0), "世界宽 = 12 屏")
	check(MirrorLake.WATERLINE_Y == SideviewMapLayout.GROUND_BASELINE_Y, "水线 = 归航镇同一条站立基线 555")
	check(MirrorLake.MAP_HEIGHT == 1110.0, "地图高 1110（约 1.54 屏）")
	check(MirrorLake.CAMERA_Y_REST == 195.0, "站地时水线在屏幕正中（camera_y=195）")
	check(MirrorLake.STAND_OFFSET_Y >= 50.0 and MirrorLake.STAND_OFFSET_Y <= 80.0, "站立线在水线下 50~80 像素（%d）" % int(MirrorLake.STAND_OFFSET_Y))
	check(MirrorLake.STAND_Y == MirrorLake.WATERLINE_Y + MirrorLake.STAND_OFFSET_Y, "站立线 = 水线 + 偏移")
	check(MirrorLake.camera_y_for(MirrorLake.STAND_Y) == MirrorLake.CAMERA_Y_REST, "站在站立线上镜头纵向不动")
	check(MirrorLake.STAND_Y - MirrorLake.CAMERA_Y_REST < MirrorLake.VIEW_HEIGHT * 0.75, "脚底在屏幕下 1/4 之上（不贴近底部 HUD）")
	check(MirrorLake.CAMERA_Y_REST + MirrorLake.VIEW_HEIGHT <= MirrorLake.MAP_HEIGHT, "镜头底边不超出贴图")
	check(MirrorLake.camera_y_for(-5000.0) == MirrorLake.CAMERA_Y_MIN, "镜头纵向上限被夹住")
	check(MirrorLake.camera_y_for(5000.0) == MirrorLake.CAMERA_Y_MAX, "镜头纵向下限被夹住")
	check(MirrorLake.CAMERA_X_MIN == 640.0 and MirrorLake.CAMERA_X_MAX == 14720.0, "镜头横向范围 [640, 14720]")
	check(MirrorLake.camera_x_for(0.0) == 640.0, "最左端镜头夹在 640")
	check(MirrorLake.camera_x_for(99999.0) <= MirrorLake.CAMERA_X_MAX, "最右端镜头不超过 14720")
	check(MirrorLake.layer_offset_x(640.0, 0.5) == 0.0, "镜头在最左端时每层都从 x=0 开始")
	check(is_equal_approx(MirrorLake.layer_offset_x(MirrorLake.CAMERA_X_MAX, 0.5), -(MirrorLake.CAMERA_X_MAX - 640.0) * 0.5),
		"中景 ratio 0.5：镜头走到头偏移 = 一半行程")
	check(MirrorLake.SPAWN_X >= MirrorLake.PLAYER_MARGIN and MirrorLake.SPAWN_X < MirrorLake.ZONE_PUZZLE_ONE_START, "出生点在入湖区、在左边界内")
	check(MirrorLake.BOSS_ARENA_CENTER_X == MirrorLake.WORLD_LENGTH - MirrorLake.VIEW_WIDTH,
		"BOSS 战场中心 = WORLD_LENGTH - 1280（美术管线按这个摆湖心楼）")


func _check_zones() -> void:
	var starts: Array = MirrorLake.ZONE_STARTS
	check(starts == [0.0, 2560.0, 7680.0, 12800.0], "四区起点 0 / 2560 / 7680 / 12800")
	check(MirrorLake.ZONE_NAMES.size() == 4 and starts.size() == 4, "四个分区：入湖 / 解谜一 / 解谜二 / BOSS")
	var widths: Array[float] = []
	for i in starts.size():
		widths.append(MirrorLake.zone_end(i) - starts[i])
	check(widths == [2560.0, 5120.0, 5120.0, 2560.0], "分区宽：入湖 2 屏 / 解谜一 4 屏 / 解谜二 4 屏 / BOSS 2 屏")
	check(MirrorLake.zone_end(MirrorLake.Zone.BOSS) == MirrorLake.WORLD_LENGTH, "BOSS 区在最右，一直到世界尽头")
	check(MirrorLake.zone_at(0.0) == MirrorLake.Zone.ENTRY and MirrorLake.zone_at(2559.0) == MirrorLake.Zone.ENTRY, "zone_at：入湖")
	check(MirrorLake.zone_at(2560.0) == MirrorLake.Zone.PUZZLE_ONE and MirrorLake.zone_at(7679.0) == MirrorLake.Zone.PUZZLE_ONE, "zone_at：解谜一")
	check(MirrorLake.zone_at(7680.0) == MirrorLake.Zone.PUZZLE_TWO and MirrorLake.zone_at(12799.0) == MirrorLake.Zone.PUZZLE_TWO, "zone_at：解谜二")
	check(MirrorLake.zone_at(12800.0) == MirrorLake.Zone.BOSS and MirrorLake.zone_at(MirrorLake.WORLD_LENGTH) == MirrorLake.Zone.BOSS, "zone_at：BOSS")
	check(MirrorLake.zone_at(MirrorLake.SPAWN_X) == MirrorLake.Zone.ENTRY, "出生点在入湖区")
	check(MirrorLake.BOSS_ARENA_CENTER_X > MirrorLake.ZONE_BOSS_START and MirrorLake.BOSS_ARENA_CENTER_X < MirrorLake.WORLD_LENGTH,
		"BOSS 战场中心落在 BOSS 区里")


func _check_boss_camera() -> void:
	var lo := MirrorLake.PLAYER_MARGIN
	var hi := MirrorLake.WORLD_LENGTH - MirrorLake.PLAYER_MARGIN
	var before_ok := true
	var visible_ok := true
	var smooth_ok := true
	var prev := MirrorLake.camera_x_for(lo)
	var x := lo
	while x <= hi:
		var cam := MirrorLake.camera_x_for(x)
		if x <= MirrorLake.ZONE_BOSS_START and not is_equal_approx(cam, clampf(x, MirrorLake.CAMERA_X_MIN, MirrorLake.CAMERA_X_MAX)):
			before_ok = false
		if absf(x - cam) > MirrorLake.BOSS_CAMERA_MAX_OFFSET + 0.01:
			visible_ok = false
		if absf(cam - prev) > 15.0:
			smooth_ok = false
		prev = cam
		x += 10.0
	check(before_ok, "BOSS 区之前镜头就是普通跟随（不被拉）")
	check(visible_ok, "整个可走范围里主角离镜头中心 ≤ 480（始终在画面里）")
	check(smooth_ok, "镜头位置随主角连续变化（每 10px 步长 ≤ 15px，即镜头最快 1.5 倍主角速度，没有跳变）")
	check(is_equal_approx(MirrorLake.camera_x_for(MirrorLake.BOSS_ARENA_CENTER_X), MirrorLake.BOSS_ARENA_CENTER_X),
		"主角站在战场中心时镜头也在战场中心")
	check(MirrorLake.camera_x_for(hi) < MirrorLake.CAMERA_X_MAX, "BOSS 区最右端镜头比普通夹取更靠左（留出余量）")
	var edge_screen_x := hi - MirrorLake.camera_x_for(hi) + MirrorLake.VIEW_WIDTH * 0.5
	check(edge_screen_x <= MirrorLake.VIEW_WIDTH - 100.0, "走到最右端时主角离右屏边 ≥ 100px（%.0f）" % edge_screen_x)


func _check_scene() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "镜湖场景能加载")
	if packed == null:
		return
	var scene := packed.instantiate() as MirrorLake
	root.add_child(scene)
	await process_frame
	check(scene.layer_sprites.size() == 4, "四层美术：宣纸 / 远景 / 中景 / 地面")
	var expected_widths := [1280, 2976, 8320, 15360]
	for i in scene.layer_sprites.size():
		var sprite := scene.layer_sprites[i]
		var ratio := scene.layer_ratios[i]
		var tex := sprite.texture
		check(tex != null and tex.get_height() == int(MirrorLake.MAP_HEIGHT), "%s 高 1110" % sprite.name)
		check(tex != null and tex.get_width() == expected_layer_width(ratio),
			"%s 宽 %d = 按世界宽算出的 %d" % [sprite.name, tex.get_width() if tex != null else 0, expected_layer_width(ratio)])
		check(expected_layer_width(ratio) == expected_widths[i], "%s 宽 = 写死的 %d（世界宽改了这里要一起改）" % [sprite.name, expected_widths[i]])
		var travel := (MirrorLake.CAMERA_X_MAX - MirrorLake.CAMERA_X_MIN) * ratio
		check(tex != null and float(tex.get_width()) >= MirrorLake.VIEW_WIDTH + travel - 0.5,
			"%s 够镜头走完全程（需 %d）" % [sprite.name, int(MirrorLake.VIEW_WIDTH + travel)])
		check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "%s 用线性过滤（水墨，不是像素）" % sprite.name)
	check(scene.layer_ratios == [0.0, 0.12, 0.5, 1.0], "视差 ratio 0 / 0.12 / 0.5 / 1.0")
	check(scene.player != null and scene.player.get_parent() == scene.world_root, "主角挂在 world_root 下")
	check(scene.player.position == Vector2(MirrorLake.SPAWN_X, MirrorLake.STAND_Y), "主角出生在站立线上")
	check(float(scene.player.get("world_min_x")) == MirrorLake.PLAYER_MARGIN
		and float(scene.player.get("world_max_x")) == MirrorLake.WORLD_LENGTH - MirrorLake.PLAYER_MARGIN, "主角左右边界")
	var world_z := scene.world_root.z_index
	var max_back := 0
	for s in scene.layer_sprites:
		max_back = maxi(max_back, s.z_index)
	check(max_back < world_z, "所有背景层都垫在世界容器下面（%d < %d）" % [max_back, world_z])
	# 脚下接触阴影：world_root 的子节点，夹在地面层(10)和主角(12)之间，跟着主角 x，贴在水线上。
	var contact := scene.water_contact
	check(contact != null and contact.get_parent() == scene.world_root, "脚下接触阴影挂在 world_root 下")
	check(contact != null and contact.texture != null and contact.texture.get_size() == Vector2(192, 48), "接触阴影贴图 192×48")
	check(contact != null and contact.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "接触阴影用线性过滤")
	check(contact != null and scene.layer_sprites[3].z_index < world_z + contact.z_index and world_z + contact.z_index < world_z + int(scene.player.z_index),
		"接触阴影的有效 z 在地面层之上、主角之下")
	check(MirrorLake.water_contact_alpha(MirrorLake.STAND_Y) == 1.0 and MirrorLake.water_contact_alpha(MirrorLake.STAND_Y - 1000.0) == 0.0,
		"站地时接触阴影不透明，跳高了淡出")
	# 走到入湖区右端 / 解谜区中间 / BOSS 战场中心 / 最右端：滚动、分区、接触阴影都要对。
	for probe_x in [900.0, 5000.0, 10000.0, MirrorLake.BOSS_ARENA_CENTER_X]:
		scene.player.position.x = probe_x
		scene._process(0.016)
		check(is_equal_approx(scene.world_root.position.x, -(MirrorLake.camera_x_for(probe_x) - 640.0)), "x=%d：world_root 随镜头滚动" % int(probe_x))
		check(is_equal_approx(scene.layer_sprites[3].position.x, scene.world_root.position.x), "x=%d：地面层和 world_root 同速" % int(probe_x))
		check(absf(contact.position.x - probe_x) < 0.01 and is_equal_approx(contact.position.y, MirrorLake.STAND_Y + 2.0), "x=%d：接触阴影跟着主角脚下" % int(probe_x))
	scene.player.position.x = 99999.0
	scene._process(0.016)
	var cam := MirrorLake.camera_x_for(99999.0)
	check(is_equal_approx(scene.world_root.position.x, -(cam - 640.0)), "主角在右端时 world_root 跟随镜头（%.0f）" % scene.world_root.position.x)
	check(is_equal_approx(scene.layer_sprites[3].position.x, scene.world_root.position.x), "地面层和 world_root 同速（ratio 1.0）")
	check(is_equal_approx(scene.layer_sprites[2].position.x, -(cam - 640.0) * 0.5), "中景层 ratio 0.5 同步偏移")
	check(scene.layer_sprites[0].position.x == 0.0, "宣纸层不随镜头横移")
	# 最远的镜头位置也不会露出贴图右边缘。
	for i in scene.layer_sprites.size():
		var spr := scene.layer_sprites[i]
		check(spr.position.x + spr.texture.get_width() >= MirrorLake.VIEW_WIDTH - 0.5, "%s 在最右端仍盖满屏幕" % spr.name)
	scene.queue_free()


# ---------------------------------------------------------------- 阴阳切换

func new_scene() -> MirrorLake:
	var scene := (load(SCENE_PATH) as PackedScene).instantiate() as MirrorLake
	root.add_child(scene)
	return scene


func _check_switch_constants() -> void:
	check(MirrorLake.camera_y_for(MirrorLake.STAND_Y) == MirrorLake.CAMERA_Y_REST, "站立线上镜头 y 不变（阴阳两面一样）")
	check(MirrorLake.camera_y_for(MirrorLake.STAND_Y - 170.0) < MirrorLake.CAMERA_Y_REST, "起跳：镜头跟着上抬")
	check(MirrorLake.water_contact_alpha(MirrorLake.STAND_Y) == 1.0 and MirrorLake.water_contact_alpha(MirrorLake.STAND_Y - 1000.0) == 0.0, "接触阴影：站地不透明，跳高淡出")
	check(MirrorLake.SWITCH_DURATION >= 0.3 and MirrorLake.SWITCH_DURATION <= 0.5, "过渡时长 0.3~0.5 秒（%.2f）" % MirrorLake.SWITCH_DURATION)
	check(MirrorLake.SWITCH_COOLDOWN > 0.0 and MirrorLake.SWITCH_COOLDOWN >= MirrorLake.SWITCH_DURATION, "冷却 > 0 且不短于过渡（待定的占位值 %.1fs）" % MirrorLake.SWITCH_COOLDOWN)
	# 输入颠倒的纯函数
	var a := MirrorLakeControlInverter.desired_state({KEY_A: true}, false)
	check(a[KEY_A] == true and a[KEY_D] == false, "不颠倒：按 A 就是 A")
	var b := MirrorLakeControlInverter.desired_state({KEY_A: true}, true)
	check(b[KEY_D] == true and b[KEY_RIGHT] == true and b[KEY_A] == false and b[KEY_LEFT] == false, "颠倒：按 A = 向右（D 和 →）")
	var c := MirrorLakeControlInverter.desired_state({KEY_LEFT: true}, true)
	check(c[KEY_D] == true and c[KEY_RIGHT] == true and c[KEY_LEFT] == false, "颠倒：按 ← = 向右")
	var d := MirrorLakeControlInverter.desired_state({KEY_W: true}, true)
	check(d[KEY_S] == true and d[KEY_DOWN] == true and d[KEY_W] == false and d[KEY_UP] == false and d[KEY_SPACE] == false, "颠倒：按 W = 向下")
	var e := MirrorLakeControlInverter.desired_state({KEY_SPACE: true}, true)
	check(e[KEY_S] == true and e[KEY_W] == false, "颠倒：按空格（跳）= 向下")
	var f := MirrorLakeControlInverter.desired_state({KEY_S: true}, true)
	check(f[KEY_W] == true and f[KEY_UP] == true and f[KEY_SPACE] == true, "颠倒：按 S = 向上（跳）")
	var g := MirrorLakeControlInverter.desired_state({KEY_A: true, KEY_D: true}, true)
	check(g[KEY_A] == true and g[KEY_D] == true, "颠倒：同时按左右仍是同时按（互换）")
	check(MirrorLakeControlInverter.desired_state({KEY_J: true}, true).size() == 9, "只管方向键：J 之类不在受控表里")


## 画面几何快照：主角 y、虚拟地面、镜头 y、水线（屏幕 y）、各层 flip_v / 位置 / 缩放。切换前后必须一样。
func geometry(scene: MirrorLake) -> Dictionary:
	var flips := []
	var scales := []
	for sprite in scene.layer_sprites:
		flips.append(sprite.flip_v)
		scales.append(sprite.scale)
	return {
		"player_y": scene.player.position.y,
		"ground_y": float(scene.player.get("ground_y")),
		"camera_y": scene.camera_y,
		"waterline_screen_y": MirrorLake.WATERLINE_Y - scene.camera_y,
		"layer_y": scene.layer_sprites[0].position.y,
		"flips": flips,
		"scales": scales,
		"contact_y": scene.water_contact.position.y,
	}


func same_geometry(a: Dictionary, b: Dictionary) -> bool:
	for key in a.keys():
		if not b.has(key):
			return false
		if typeof(a[key]) == TYPE_FLOAT:
			if not is_equal_approx(a[key], b[key]):
				return false
		elif a[key] != b[key]:
			return false
	return a.size() == b.size()


func _check_switch_state() -> void:
	var scene := new_scene()
	await process_frame
	scene.set_process(false) # 手动推进时间，结果可重复
	check(InputMap.has_action(MirrorLake.SWITCH_ACTION), "输入动作 mirror_switch 存在")
	var has_f := false
	for ev in InputMap.action_get_events(MirrorLake.SWITCH_ACTION):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F:
			has_f = true
	check(has_f, "mirror_switch 默认键 = F")
	check(scene.side == MirrorLake.Side.YANG and not scene.is_switching() and scene.can_switch(), "初始：阳面、没在过渡、可切换")
	check(not scene.controls_inverted() and scene.controls_inverted_enabled, "初始：不颠倒（总开关默认开）")
	check(MirrorLake.zone_at(scene.player.position.x) == MirrorLake.Zone.ENTRY, "初始：出生在入口区")
	scene._process(0.016)
	var before := geometry(scene)
	check(is_equal_approx(before["player_y"], MirrorLake.STAND_Y) and is_equal_approx(before["camera_y"], MirrorLake.CAMERA_Y_REST), "切换前：主角在站立线 619、镜头 y=195")
	check(is_equal_approx(before["waterline_screen_y"], 360.0), "切换前：水线在屏幕 y=360")
	check(not scene.ink_transition.yin and not scene.ink_transition.active, "初始：画面是阳（遮罩没在过渡）")
	check(scene.request_switch(), "切换：成功")
	check(scene.side == MirrorLake.Side.YIN and scene.is_switching(), "切换：状态翻成阴、开始过渡")
	check(scene.switch_cooldown_left == MirrorLake.SWITCH_COOLDOWN, "切换：冷却从按下起算")
	check(not scene.controls_inverted() and not scene.control_inverter.inverted, "入口区阴面：强制不颠倒")
	# 离开入口进入解谜一后，总开关开 + 阴面 → 恢复颠倒
	scene.player.position.x = MirrorLake.ZONE_PUZZLE_ONE_START + 80.0
	scene._process(0.0)
	check(scene.controls_inverted() and scene.control_inverter.inverted, "离开入口到解谜一：阴面恢复操作颠倒")
	scene.player.position.x = MirrorLake.SPAWN_X
	scene._process(0.0)
	check(not scene.controls_inverted() and not scene.control_inverter.inverted, "回到入口：再次关闭颠倒")
	check(not scene.request_switch() and scene.side == MirrorLake.Side.YIN, "过渡/冷却期间再按：无效，仍是阴")
	scene.advance_switch(MirrorLake.SWITCH_DURATION * 0.25)
	check(is_equal_approx(scene.transition_progress(), 0.25), "过渡 25%")
	check(scene.ink_transition.active and is_equal_approx(scene.ink_transition.progress, 0.25), "25%：墨迹过渡进行中")
	var mat := scene.ink_transition.shader_material
	check(mat != null and is_equal_approx(float(mat.get_shader_parameter("prev_yin")), 0.0) and is_equal_approx(float(mat.get_shader_parameter("next_yin")), 1.0), "25%：shader 从阳到阴")
	var all_material := true
	for sprite in scene.layer_sprites:
		if sprite.material != mat:
			all_material = false
	check(all_material, "背景四层都挂着同一个墨迹材质")
	check(scene.player.material == null, "主角本体不挂反转材质（不参与反转）")
	scene.advance_switch(MirrorLake.SWITCH_DURATION * 0.3)
	scene._process(0.0)
	var mid := geometry(scene)
	check(same_geometry(mid, before), "过渡中（55%）：主角 y / 镜头 y / 水线 / 各层几何都没变")
	scene.advance_switch(MirrorLake.SWITCH_DURATION * 0.5)
	check(not scene.is_switching() and not scene.ink_transition.active and scene.ink_transition.yin, "过渡结束：稳定在阴面")
	check(is_equal_approx(float(mat.get_shader_parameter("progress")), 1.0) and is_equal_approx(float(mat.get_shader_parameter("next_yin")), 1.0), "稳定阴面：shader progress=1、next=阴")
	scene._process(0.016)
	var after := geometry(scene)
	check(is_equal_approx(after["player_y"], before["player_y"]), "切换后：主角 y 不变（%d）" % int(after["player_y"]))
	check(is_equal_approx(after["camera_y"], before["camera_y"]) and is_equal_approx(after["camera_y"], MirrorLake.CAMERA_Y_REST), "切换后：镜头 y 不变（195）")
	check(is_equal_approx(after["waterline_screen_y"], before["waterline_screen_y"]), "切换后：水线屏幕 y 不变（360）")
	check(same_geometry(after, before), "切换后：地面 / 各层 flip / 位置 / 缩放 / 接触阴影整体不变")
	check(scene.player.scale.y > 0.0 and scene.player.rotation == 0.0, "主角本身不翻、不转")
	# 冷却
	check(scene.switch_cooldown_left > 0.0 and not scene.can_switch() and not scene.request_switch(), "冷却中：不能切")
	scene.advance_switch(scene.switch_cooldown_left - 0.01)
	check(not scene.can_switch() and not scene.request_switch(), "冷却差一点点：仍不能切")
	scene.advance_switch(0.02)
	check(is_equal_approx(scene.switch_cooldown_left, 0.0) and scene.can_switch(), "冷却结束：可以再切")
	check(scene.request_switch() and scene.side == MirrorLake.Side.YANG, "再切：回到阳面")
	check(not scene.controls_inverted() and not scene.control_inverter.inverted, "阳面：操作恢复正常")
	scene.advance_switch(MirrorLake.SWITCH_DURATION * 0.5)
	check(is_equal_approx(float(mat.get_shader_parameter("prev_yin")), 1.0) and is_equal_approx(float(mat.get_shader_parameter("next_yin")), 0.0), "切回过程：shader 从阴到阳")
	scene.advance_switch(MirrorLake.SWITCH_DURATION)
	scene._process(0.016)
	check(not scene.ink_transition.yin and not scene.ink_transition.active and same_geometry(geometry(scene), before), "回阳面：画面恢复，几何仍与最初一致")
	# 起跳中切换：主角位置本来就不动，所以高度保持
	scene.advance_switch(MirrorLake.SWITCH_COOLDOWN)
	scene.player.position.y = MirrorLake.STAND_Y - 100.0
	scene.request_switch()
	scene.advance_switch(MirrorLake.SWITCH_DURATION * 0.6)
	check(is_equal_approx(scene.player.position.y, MirrorLake.STAND_Y - 100.0), "空中切换：主角 y 不变（离地高度保持 100px）")
	# 总开关（在解谜一测，避开入口区强制不颠倒）
	scene.player.position.x = MirrorLake.ZONE_PUZZLE_ONE_START + 80.0
	scene._process(0.0)
	scene.controls_inverted_enabled = false
	check(scene.side == MirrorLake.Side.YIN and not scene.controls_inverted() and not scene.control_inverter.inverted, "总开关关：阴面也不颠倒")
	scene.controls_inverted_enabled = true
	check(scene.controls_inverted() and scene.control_inverter.inverted, "总开关开：阴面颠倒（解谜一）")
	scene.queue_free()
	await process_frame


## 日月互换：阳 = 落日、阴 = 月亮；独立精灵、与 01_paper 同视差、纸底里没有烤着的红日。
func _check_celestials() -> void:
	var scene := new_scene()
	await process_frame
	scene.set_process(false)
	check(scene.sun_sprite != null and scene.moon_sprite != null, "有落日、月亮两个独立精灵")
	check(scene.sun_sprite.material != scene.ink_transition.shader_material and scene.moon_sprite.material != scene.ink_transition.shader_material, "日月不挂明暗反转材质（用自己的淡变材质）")
	var sun_mat := scene.sun_sprite.material as ShaderMaterial
	var moon_mat := scene.moon_sprite.material as ShaderMaterial
	check(int(sun_mat.get_shader_parameter("celestial_mode")) == 1 and int(moon_mat.get_shader_parameter("celestial_mode")) == 2, "落日 mode=1（阳可见），月亮 mode=2（阴可见）")
	check(celestial_visible(sun_mat) > 0.99 and celestial_visible(moon_mat) < 0.01, "阳态：只有落日，没有月亮")
	# 位置：圆心 = 配置的位置；ratio 0，不随镜头 x 动；随镜头 y 跟纸底一起动
	scene._process(0.016)
	var paper := scene.layer_sprites[0]
	var sun_center := scene.sun_sprite.position + scene.sun_sprite.texture.get_size() * 0.5
	check(sun_center.is_equal_approx(MirrorLake.SUN_CENTER + paper.position), "落日圆心 = SUN_CENTER 随纸底（视差 0）")
	var moon_center := scene.moon_sprite.position + scene.moon_sprite.texture.get_size() * 0.5
	check(moon_center.is_equal_approx(MirrorLake.MOON_CENTER + paper.position), "月亮圆心 = MOON_CENTER 随纸底（视差 0）")
	scene.camera_x = MirrorLake.CAMERA_X_MAX
	scene.update_scroll()
	check(is_equal_approx(scene.sun_sprite.position.x, scene.moon_sprite.position.x) and is_equal_approx(scene.sun_sprite.position.x - MirrorLake.SUN_CENTER.x + 128.0, paper.position.x), "镜头走到最右，日月仍和纸底相对固定")
	# 过渡：交叉淡变，终态互换
	scene.request_switch()
	scene.advance_switch(MirrorLake.SWITCH_DURATION * 0.5)
	check(int(sun_mat.get_shader_parameter("prev_yin")) == 0 and int(sun_mat.get_shader_parameter("next_yin")) == 1 and float(sun_mat.get_shader_parameter("progress")) < 1.0, "过渡中：日月材质同步进度（同一个遮罩）")
	scene.advance_switch(MirrorLake.SWITCH_DURATION)
	check(celestial_visible(sun_mat) < 0.01 and celestial_visible(moon_mat) > 0.99, "阴态：只有月亮，没有落日")
	scene.advance_switch(MirrorLake.SWITCH_COOLDOWN)
	scene.request_switch()
	scene.advance_switch(MirrorLake.SWITCH_DURATION * 2.0)
	check(celestial_visible(sun_mat) > 0.99 and celestial_visible(moon_mat) < 0.01, "切回阳态：落日回来、月亮消失")
	# 贴图：落日偏红，月亮偏银白；纸底里不再有烤死的红日
	var sun_px := scene.sun_sprite.texture.get_image().get_pixel(128, 128)
	var moon_px := scene.moon_sprite.texture.get_image().get_pixel(128, 100)
	check(sun_px.r - sun_px.b > 0.3 and sun_px.a > 0.5, "落日贴图偏朱砂红")
	check(moon_px.a > 0.9 and moon_px.r > 0.75 and absf(moon_px.r - moon_px.b) < 0.1, "月亮贴图是浅银白")
	var paper_px := paper.texture.get_image().get_pixel(int(MirrorLake.SUN_CENTER.x), int(MirrorLake.SUN_CENTER.y))
	check(paper_px.r - paper_px.b < 0.15, "纸底在落日位置没有红日（日是独立精灵）")
	scene.queue_free()
	await process_frame


## 日月材质当前"该有多可见"：落日 = 1 - 阴程度，月亮 = 阴程度（稳定态下 progress = 1，阴程度 = next_yin）。
func celestial_visible(mat: ShaderMaterial) -> float:
	var yin_amount := float(mat.get_shader_parameter("next_yin"))
	return 1.0 - yin_amount if int(mat.get_shader_parameter("celestial_mode")) == 1 else yin_amount


## 真实输入：F 键切换；颠倒开/关时 A/D 对主角的实际效果。
func _check_switch_input() -> void:
	var scene := new_scene()
	await process_frame
	await process_frame
	var press_f := InputEventKey.new()
	press_f.physical_keycode = KEY_F
	press_f.keycode = KEY_F
	press_f.pressed = true
	Input.parse_input_event(press_f)
	await process_frame
	await process_frame
	check(scene.side == MirrorLake.Side.YIN, "按 F：切到阴面")
	var release_f := press_f.duplicate() as InputEventKey
	release_f.pressed = false
	Input.parse_input_event(release_f)
	await process_frame
	check(not scene.control_inverter.inverted, "入口区阴面：输入层不颠倒")
	# 移到解谜一再测真实颠倒输入
	scene.player.position.x = MirrorLake.ZONE_PUZZLE_ONE_START + 120.0
	scene._process(0.0)
	await process_frame
	check(scene.control_inverter.inverted, "解谜一阴面：输入层颠倒已开启")
	# 颠倒中真实按 A → 主角读到 D
	await _key(KEY_A, true)
	check(Input.is_physical_key_pressed(KEY_D) and not Input.is_physical_key_pressed(KEY_A), "颠倒：真实按 A → 物理键读成 D")
	check(Input.is_action_pressed(&"move_right") and not Input.is_action_pressed(&"move_left"), "颠倒：move_right 生效、move_left 不生效")
	await _key(KEY_A, false)
	await _key(KEY_LEFT, true)
	check(Input.is_action_pressed("ui_right") and not Input.is_action_pressed("ui_left"), "颠倒：真实按 ← → ui_right 生效、ui_left 不生效（主角读的就是这两个）")
	await _key(KEY_LEFT, false)
	check(not Input.is_action_pressed("ui_right") and not Input.is_action_pressed("ui_left"), "松开 ←：动作都松开")
	await _key(KEY_A, true)
	var x0 := scene.player.position.x
	await create_timer(0.35).timeout
	check(scene.player.position.x > x0 + 5.0, "颠倒：按 A 主角向右跑（%.0f → %.0f）" % [x0, scene.player.position.x])
	# 按着键时关掉总开关：立刻恢复成按 A = 向左
	scene.controls_inverted_enabled = false
	await process_frame
	check(Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_D), "按着 A 时关总开关：恢复成 A")
	await _key(KEY_A, false)
	check(not Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_D), "松开 A：两个键都松开")
	# 总开关关：阴面按 A 就是向左
	await _key(KEY_A, true)
	check(Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_D), "总开关关：阴面按 A 仍是 A")
	await _key(KEY_A, false)
	# 空格/W（跳）↔ S（下）
	scene.controls_inverted_enabled = true
	await process_frame
	await _key(KEY_W, true)
	check(Input.is_physical_key_pressed(KEY_S) and not Input.is_physical_key_pressed(KEY_W), "颠倒：真实按 W → 物理键读成 S（向下）")
	await _key(KEY_W, false)
	check(not Input.is_physical_key_pressed(KEY_S), "松开 W：S 也松开")
	# 离开场景：恢复，不留下"卡住的键"
	await _key(KEY_D, true)
	scene.queue_free()
	await process_frame
	await process_frame
	check(Input.is_physical_key_pressed(KEY_D) and not Input.is_physical_key_pressed(KEY_A), "离开场景：按着 D 时恢复成真实状态")
	await _key(KEY_D, false)
	check(not Input.is_physical_key_pressed(KEY_D) and not Input.is_physical_key_pressed(KEY_A), "松开后没有卡键")


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
