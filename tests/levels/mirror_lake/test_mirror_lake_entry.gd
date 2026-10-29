extends SceneTree

## 镜湖入口区玩法：区内与全图一致阴面颠倒、拱桥断桥对准印、阳态印水下隐影、阴态清晰可踩、
## 多丛芦苇门封路（桥面二段跳越不过）、无文字提示。
## 用法：homeing-star-test/run-tests.ps1 -Test test_mirror_lake_entry

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


func new_scene() -> MirrorLake:
	var scene := (load(SCENE_PATH) as PackedScene).instantiate() as MirrorLake
	root.add_child(scene)
	return scene


func run() -> void:
	await _check_entry_inversion()
	await _check_broken_bridge()
	await _check_seal_and_gate()
	await _check_gate_fully_blocks()
	await _check_no_text_hints()
	print("")
	print("结果：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_entry_inversion() -> void:
	var scene := new_scene()
	await process_frame
	scene.set_process(false)
	check(scene.entry != null, "入口玩法节点存在")
	check(MirrorLake.zone_at(scene.player.position.x) == MirrorLake.Zone.ENTRY, "出生在入口区")
	check(scene.controls_inverted_enabled, "总开关默认仍为 true（全局默认不变）")
	check(not scene.controls_inverted(), "入口阳面：不颠倒")
	check(scene.request_switch() and scene.side == MirrorLake.Side.YIN, "入口内切到阴面")
	check(scene.controls_inverted() and scene.control_inverter.inverted, "入口阴面：颠倒（与全图一致）")
	scene.player.position.x = MirrorLake.ZONE_PUZZLE_ONE_START + 40.0
	check(scene.controls_inverted() and scene.control_inverter.inverted, "进入解谜一：阴面仍颠倒")
	scene.player.position.x = MirrorLake.SPAWN_X
	check(scene.controls_inverted() and scene.control_inverter.inverted, "回到入口：仍颠倒")
	scene.player.position.x = MirrorLake.ZONE_PUZZLE_ONE_START + 40.0
	scene.controls_inverted_enabled = false
	check(not scene.controls_inverted(), "总开关关：解谜一阴面也不颠倒")
	scene.queue_free()
	await process_frame


func _check_broken_bridge() -> void:
	var scene := new_scene()
	await process_frame
	scene.set_process(false)
	var entry := scene.entry
	check(entry.bridge != null, "断桥节点存在")
	check(entry.bridge_left_sprite != null and entry.bridge_left_sprite.texture != null, "拱桥左段正式贴图")
	check(entry.bridge_right_sprite != null and entry.bridge_right_sprite.texture != null, "拱桥右段正式贴图")
	check(entry.get_node_or_null("BrokenBridge/PlaceholderTag") == null, "无 PLACEHOLDER 桥标签")
	check(entry.gap_covers_seal(), "缺口覆盖朱红印 x")
	check(entry.bridge_butts_gate(), "桥尽顶着芦苇门（右缘=GATE_X）")
	check(entry.bridge_surfaces_registered, "断桥站立面已注册")
	check(entry.bridge_allows_water_bypass(), "桥未登记 solid_blocker（水面可绕行）")
	# 一段结构：恰好两段地面，不是三处散点台阶。
	var surfaces: Array = scene.player.ground_surfaces
	var bridge_hits := 0
	for s in surfaces:
		if s == entry.bridge_left_surface or s == entry.bridge_right_surface:
			bridge_hits += 1
	check(bridge_hits == 2, "恰好两段桥面 ground_surface（非散点）")
	check(is_equal_approx(entry.bridge_left_surface.position.y, MirrorLakeEntry.BRIDGE_DECK_Y), "左桥面顶=BRIDGE_DECK_Y")
	check(is_equal_approx(entry.bridge_right_surface.position.y, MirrorLakeEntry.BRIDGE_DECK_Y), "右桥面顶=BRIDGE_DECK_Y")
	check(entry.bridge_left_surface.end.x <= MirrorLakeEntry.SEAL_X, "左段止于缺口左缘（印左侧）")
	check(entry.bridge_right_surface.position.x >= MirrorLakeEntry.SEAL_X, "右段起于缺口右缘（印右侧）")
	check(is_equal_approx(entry.bridge_right_surface.end.x, MirrorLakeEntry.GATE_X), "右段右缘=GATE_X")
	# 碰撞与视觉对齐：贴图锚在甲板顶。
	check(is_equal_approx(entry.bridge_left_sprite.position.y, MirrorLakeEntry.BRIDGE_DECK_Y), "左贴图顶对齐甲板")
	check(is_equal_approx(entry.bridge_right_sprite.position.y, MirrorLakeEntry.BRIDGE_DECK_Y), "右贴图顶对齐甲板")
	# 拱桥贴图应高于旧平甲板（约 110），含拱腹/栏。
	var left_h: float = float(entry.bridge_left_sprite.texture.get_height())
	var right_h: float = float(entry.bridge_right_sprite.texture.get_height())
	check(left_h >= 140.0, "左拱桥贴图含拱腹高度（h=%.0f）" % left_h)
	check(right_h >= 140.0, "右拱桥贴图含拱腹高度（h=%.0f）" % right_h)
	# 缺口内无桥面：站在印 x 应回落到虚拟水面。
	scene.player.position = Vector2(MirrorLakeEntry.SEAL_X, MirrorLakeEntry.BRIDGE_DECK_Y)
	var snap_gap: float = scene.player.resolve_ground_snap_y()
	check(is_equal_approx(snap_gap, scene.player.ground_y) or snap_gap >= MirrorLake.STAND_Y - 1.0, "缺口内无桥面，snap 回水面（snap=%.0f）" % snap_gap)
	# 桥面上可站。
	var mid_left: float = (MirrorLakeEntry.BRIDGE_LEFT_X + MirrorLakeEntry.bridge_left_end()) * 0.5
	scene.player.position = Vector2(mid_left, MirrorLakeEntry.BRIDGE_DECK_Y)
	var snap_deck: float = scene.player.resolve_ground_snap_y()
	check(is_equal_approx(snap_deck, MirrorLakeEntry.BRIDGE_DECK_Y), "左桥面可站（snap=%.0f）" % snap_deck)
	# 水面绕行：站立线高度 clamp 不被桥挡住，可走到印 x。
	scene.player.position = Vector2(MirrorLakeEntry.SEAL_X, MirrorLake.STAND_Y)
	var bypass_x: float = scene.player.clamp_position_x()
	check(absf(bypass_x - MirrorLakeEntry.SEAL_X) < 1.0, "水面可走到印位（x=%.0f）" % bypass_x)
	scene.queue_free()
	await process_frame


func _check_seal_and_gate() -> void:
	var scene := new_scene()
	await process_frame
	scene.set_process(false)
	var entry := scene.entry
	check(entry != null and not entry.seal_activated and not entry.gate_open, "初始：印未踩、门未开")
	check(entry.is_gate_blocking(), "初始：芦苇门软挡已注册")
	check(entry.seal_sprite != null and entry.seal_sprite.texture != null, "朱红印使用正式贴图")
	check(entry.gate_sprite != null and entry.gate_sprite.texture != null, "芦苇门使用正式贴图")
	check(entry.get_node_or_null("VermilionSeal/PlaceholderTag") == null, "无 PLACEHOLDER 印标签")
	check(entry.get_node_or_null("ReedGate/PlaceholderTag") == null, "无 PLACEHOLDER 门标签")
	check(scene.side == MirrorLake.Side.YANG, "初始阳面")
	entry.refresh_seal_visibility()
	check(entry.is_seal_yang_ghost_visible(), "阳态：印可见但很淡（水下隐影）")
	check(entry.seal.position.y > MirrorLake.WATERLINE_Y, "阳态：印 y 在水线以下")
	check(entry.seal.position.y > MirrorLake.STAND_Y, "阳态：印比站立线更深（沉在水下）")
	scene.side = MirrorLake.Side.YIN
	entry.refresh_seal_visibility()
	check(entry.is_seal_yin_clear(), "阴态：印清晰可踩")
	check(is_equal_approx(entry.seal.modulate.a, 1.0), "阴态：朱红印 alpha=1")
	scene.side = MirrorLake.Side.YANG
	scene.player.position = Vector2(MirrorLakeEntry.SEAL_X, MirrorLake.STAND_Y)
	entry.tick(0.016)
	check(not entry.seal_activated and not entry.gate_open, "阳态踩印位：不开门")
	scene.player.position = Vector2(MirrorLakeEntry.GATE_X + 10.0, MirrorLake.STAND_Y)
	var blocked_x: float = scene.player.clamp_position_x()
	check(blocked_x <= MirrorLakeEntry.GATE_X, "未开门：clamp 后不能越过门左缘（%.0f）" % blocked_x)
	scene.side = MirrorLake.Side.YIN
	entry.refresh_seal_visibility()
	scene.player.position = Vector2(MirrorLakeEntry.SEAL_X, MirrorLake.STAND_Y)
	entry.tick(0.016)
	check(entry.seal_activated and entry.gate_open, "阴态踩印：开门")
	check(not entry.is_gate_blocking(), "开门后：软挡已注销")
	scene.player.position = Vector2(MirrorLake.ZONE_PUZZLE_ONE_START + 20.0, MirrorLake.STAND_Y)
	var open_x: float = scene.player.clamp_position_x()
	check(open_x >= MirrorLake.ZONE_PUZZLE_ONE_START, "开门后：可到达解谜一（%.0f）" % open_x)
	entry.tick(MirrorLakeEntry.GATE_OPEN_DURATION)
	check(entry.gate_open_progress >= 1.0 and not entry.gate.visible, "开门动画结束：门淡出隐藏")
	scene.queue_free()
	await process_frame


func _check_gate_fully_blocks() -> void:
	var scene := new_scene()
	await process_frame
	scene.set_process(false)
	var entry := scene.entry
	var top_y: float = MirrorLakeEntry.gate_top_y()
	var bridge_dj_peak_y: float = MirrorLakeEntry.bridge_double_jump_peak_y()
	var water_dj_peak_y: float = MirrorLakeEntry.water_double_jump_peak_y()
	check(entry.gate_blocker.size.x >= 240.0, "门阻挡宽度足够盖住多丛（%.0f）" % entry.gate_blocker.size.x)
	check(entry.gate_blocker.position.y <= bridge_dj_peak_y - 8.0, "门阻挡顶略高于桥面二段跳顶点（top=%.0f, bridge_dj=%.0f）" % [entry.gate_blocker.position.y, bridge_dj_peak_y])
	check(is_equal_approx(entry.gate_blocker.position.y, top_y), "门阻挡顶等于 gate_top_y()（%.0f）" % entry.gate_blocker.position.y)
	check(entry.gate_blocker.end.y >= MirrorLake.STAND_Y + 20.0, "门阻挡底插入站立线以下（end=%.0f）" % entry.gate_blocker.end.y)
	# 水面站立各高度封门
	var probe_x := MirrorLakeEntry.GATE_X + MirrorLakeEntry.GATE_WIDTH * 0.5
	var water_dys: Array = [0.0, -40.0, -80.0, -103.0, -140.0, -180.0, -206.0, -220.0]
	for dy in water_dys:
		var py: float = MirrorLake.STAND_Y + dy
		if py <= entry.gate_blocker.position.y:
			continue
		scene.player.position = Vector2(probe_x, py)
		var cx: float = scene.player.clamp_position_x()
		check(cx <= MirrorLakeEntry.GATE_X or cx >= MirrorLakeEntry.GATE_X + MirrorLakeEntry.GATE_WIDTH, "关门水面：y=STAND%+.0f 时不能停在门内（x=%.0f）" % [dy, cx])
		check(entry.blocks_at_y(py), "关门水面：blocks_at_y(STAND%+.0f)" % dy)
	# ★ 站在右桥桥面上二段跳也无法过门
	var bridge_dys: Array = [0.0, -40.0, -80.0, -120.0, -160.0, -180.0, -206.0, -220.0, -240.0]
	for dy in bridge_dys:
		var py2: float = MirrorLakeEntry.BRIDGE_DECK_Y + dy
		if py2 <= entry.gate_blocker.position.y:
			continue
		scene.player.position = Vector2(probe_x, py2)
		var cx2: float = scene.player.clamp_position_x()
		check(cx2 <= MirrorLakeEntry.GATE_X or cx2 >= MirrorLakeEntry.GATE_X + MirrorLakeEntry.GATE_WIDTH, "关门桥面：y=DECK%+.0f 时不能停在门内（x=%.0f）" % [dy, cx2])
		check(entry.blocks_at_y(py2), "关门桥面：blocks_at_y(DECK%+.0f)" % dy)
	# 右桥落脚点处，二段跳顶点仍被挡
	var mid_right: float = (MirrorLakeEntry.bridge_right_x() + MirrorLakeEntry.GATE_X) * 0.5
	scene.player.position = Vector2(mid_right, MirrorLakeEntry.BRIDGE_DECK_Y)
	var snap_right: float = scene.player.resolve_ground_snap_y()
	check(is_equal_approx(snap_right, MirrorLakeEntry.BRIDGE_DECK_Y), "右桥面可站（snap=%.0f）" % snap_right)
	scene.player.position = Vector2(probe_x, bridge_dj_peak_y + 4.0)
	var cx_peak: float = scene.player.clamp_position_x()
	check(cx_peak <= MirrorLakeEntry.GATE_X or cx_peak >= MirrorLakeEntry.GATE_X + MirrorLakeEntry.GATE_WIDTH, "桥面二段跳顶点仍被门挡（x=%.0f）" % cx_peak)
	check(entry.gate.position.y >= MirrorLake.STAND_Y + 30.0, "门锚点沉入水面（y=%.0f）" % entry.gate.position.y)
	check(entry.gate_sprite != null and entry.gate_sprite.texture != null, "门贴图已加载")
	var tex_h: float = float(entry.gate_sprite.texture.get_height()) * entry.gate_sprite.scale.y
	var tex_w: float = entry.gate_display_width()
	var visual_top: float = entry.gate.position.y - tex_h
	check(tex_h >= 340.0, "门显示高度够挡桥面二段跳（h=%.0f）" % tex_h)
	check(tex_w >= 300.0, "门显示宽度覆盖多丛（w=%.0f）" % tex_w)
	check(visual_top <= bridge_dj_peak_y - 8.0, "门视觉顶略高于桥面二段跳（visual_top=%.0f, bridge_dj=%.0f）" % [visual_top, bridge_dj_peak_y])
	# 视觉顶与 blocker 顶大致对齐（允许贴图 tip 略高）
	check(absf(visual_top - top_y) <= 30.0, "blocker 与视觉顶大致对齐（visual=%.0f top=%.0f）" % [visual_top, top_y])
	# 仍远低于「通天」：不超过竹梢量级（相对水面抬升 < 420）
	check(tex_h <= 420.0, "门非通天实体墙（h=%.0f）" % tex_h)
	check(visual_top < water_dj_peak_y, "门顶高于水面二段跳（对照）")
	check(is_equal_approx(entry.gate_sprite.scale.y, MirrorLakeEntry.GATE_SPRITE_SCALE), "门 scale 与常量一致")
	scene.queue_free()
	await process_frame


func _check_no_text_hints() -> void:
	var scene := new_scene()
	await process_frame
	scene.set_process(false)
	var entry := scene.entry
	check(entry.get_node_or_null("EntryHintLabel") == null, "入口节点下无 EntryHintLabel")
	var layer := scene.get_node_or_null("DebugLayer")
	var hint_on_debug := false
	if layer != null:
		hint_on_debug = layer.get_node_or_null("EntryHintLabel") != null
	check(not hint_on_debug, "DebugLayer 上无入口教学 EntryHintLabel")
	check(scene.get_node_or_null("EntryHintLayer") == null, "无 EntryHintLayer")
	check(scene.request_switch(), "切一次阴面")
	check(entry.switched_once, "已记录本局切过一次")
	scene.player.position = Vector2(MirrorLakeEntry.GATE_X - 10.0, MirrorLake.STAND_Y)
	entry.tick(0.016)
	check(scene.get_node_or_null("EntryHintLayer") == null, "顶门后仍无提示层")
	scene.side = MirrorLake.Side.YIN
	scene.player.position = Vector2(MirrorLakeEntry.SEAL_X, MirrorLake.STAND_Y)
	entry.tick(0.016)
	check(entry.gate_open, "踩印仍可开门（无文案依赖）")
	scene.queue_free()
	await process_frame
