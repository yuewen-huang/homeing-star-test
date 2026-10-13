extends SceneTree
# Concept screenshots only. Real body poses are sampled in the dedicated room;
# root drawings use the existing RootSpikeVolley with hit resolution disabled.
class DesignRoots extends RootSpikeVolley:
	func _draw_warning_ring(spike: Dictionary) -> void:
		if _time < spike.warn_at or _time >= spike.erupt_at: return
		var progress: float = (_time - spike.warn_at) / (spike.erupt_at - spike.warn_at)
		var radius: float = spike.width * PIXEL * 0.4 + 8
		var center := Vector2(spike.x, ground_y - PIXEL)
		_draw_pixel_ellipse(center, radius, 7, Color(0.85, 0.68, 0.25, 0.25), true)
		_draw_pixel_ellipse(center, radius * lerpf(2.2, 1, progress), 7 * lerpf(2.2, 1, progress), Color("d9ad52"), false)

class ConceptOverlay extends Node2D:
	var mound := Vector2.ZERO
	var mound_growth := 0.0
	var return_path := PackedVector2Array()
	func _draw() -> void:
		if mound_growth > 0:
			var points := PackedVector2Array()
			for i in 25:
				var t := float(i) / 24
				points.append(mound + Vector2(-44 + 88 * t, -sin(t * PI) * 52 * mound_growth))
			points.append(mound + Vector2(44, 0))
			points.append(mound + Vector2(-44, 0))
			draw_colored_polygon(points, Color("789151"))
			draw_polyline(points, Color("bfd17d"), 4)
		if not return_path.is_empty():
			draw_polyline(return_path, Color("b8c478"), 5)

var room
var deer: DeerBoss
var overlay: ConceptOverlay
var volleys: Array[DesignRoots] = []
var label: Label
var output := ""
var contacts: Array[Dictionary] = []
var seen: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func clear_concept() -> void:
	for roots in volleys:
		if is_instance_valid(roots): roots.queue_free()
	volleys.clear()
	overlay.mound_growth = 0
	overlay.return_path.clear()
	overlay.queue_redraw()

func tick(count: int, sample := false) -> void:
	for i in count:
		deer._physics_process(1.0 / 60)
		deer.vfx._process(1.0 / 60)
		if sample and deer.attack_hitbox.attack != null:
			var attack: CombatAttackData = deer.attack_hitbox.attack
			if not seen.has(attack.get_instance_id()):
				seen[attack.get_instance_id()] = true
				contacts.append({"time":deer.combo_elapsed, "frame":deer.animated_sprite.frame,
					"damage":attack.health_damage, "animation":String(deer.animated_sprite.animation)})

func roots_at(xs: Array, warnings: Array, eruptions: Array, heights: Array, age: float) -> DesignRoots:
	var roots := DesignRoots.new()
	roots.setup(555, room.player.get_node("Hurtbox") as CombatHurtbox2D, deer,
		CombatAttackData.new(&"root_design_no_damage", deer, 0, 0, 0, 0, CombatAttackData.DangerType.UNPARRYABLE_DANGER))
	roots._rng.seed = 20261010
	roots.hit_target = true
	roots.set_process(false)
	for i in xs.size(): roots.add_spike(xs[i], warnings[i], eruptions[i], heights[i])
	roots._time = age
	room.specimen.add_child(roots)
	roots.set_process(false)
	volleys.append(roots)
	roots.queue_redraw()
	return roots

func snapshot(name: String, text: String) -> void:
	label.text = "根阶段 · 设计摆位（不结算伤害）\n" + text
	overlay.queue_redraw()
	deer.vfx.hide()
	(get_root().get_node("CombatFeedback") as CombatFeedbackService).clear_body_reaction(deer.animated_sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)
	print("CAPTURED ", name)

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	deer = room.adapter.boss as DeerBoss
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.player.set_physics_process(false)
	room.set_physics_process(false)
	room.set_process(false)
	for child in room.get_children():
		if child is CanvasLayer: child.hide()
	room.dummy.hide()
	room.show_grid = false
	room.queue_redraw()
	var layer := CanvasLayer.new()
	layer.layer = 900
	room.add_child(layer)
	var background := ColorRect.new()
	background.size = Vector2(1280, 110)
	background.color = Color("171b1a")
	layer.add_child(background)
	label = Label.new()
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 22)
	layer.add_child(label)
	overlay = ConceptOverlay.new()
	overlay.z_index = 13
	room.specimen.add_child(overlay)

	room.adapter.select_combo(1)
	room.play_action(2)
	tick(300, true)
	assert(contacts.size() == 3 and contacts[0].damage == 12 and contacts[1].damage == 12 and contacts[2].damage == 20)
	var data := FileAccess.open(output.path_join("sampled_combo_contacts.json"), FileAccess.WRITE)
	data.store_string(JSON.stringify(contacts, "\t"))
	data.close()

	room.play_action(0)
	tick(38)
	overlay.mound = deer.position + Vector2(deer._anchor_offset(&"light_ING",1,"hoof").x, 0)
	overlay.mound_growth = 0.45
	await snapshot("01_nodule_rise", "轻跺落地 → 根瘤向上拱出 · 0.12 s 成长 / 6 s 保持")
	tick(4)
	overlay.mound_growth = 1
	await snapshot("02_nodule_hold", "低根瘤约 88 × 52 · 可站、可跳、可一击打碎")

	clear_concept()
	room.play_action(1)
	tick(104)
	var hoof := deer.position.x + deer._anchor_offset(&"heavy_ING",0,"hoof").x
	var xs: Array = []
	var warnings: Array = []
	var eruptions: Array = []
	var heights: Array = []
	for i in 8:
		xs.append(hoof + deer.direction * (120 + i * 64))
		warnings.append(0.04 + i * 0.09)
		eruptions.append(0.46 + i * 0.09)
		heights.append(36)
	var wave := roots_at(xs, warnings, eruptions, heights, 0.30)
	await snapshot("03_line_warning", "重踩 → 裂纹沿前方传递 · 每根预警 0.42 s")
	tick(21)
	wave._time = 0.68
	wave.queue_redraw()
	await snapshot("04_line_erupt", "根刺从近到远依次上冲 · 最高约 72 / 整波最多一次伤害")

	clear_concept()
	deer.position.x = 980
	deer._show_clip(&"roar_ING", 4)
	room.player.position.x = 530
	var tracking := roots_at([498.0,530.0,562.0], [0.0,0.0,0.0], [0.6,0.6,0.6], [38,45,38], 0.40)
	await snapshot("05_tracking_warning", "根潮追猎 · 预警位置锁在脚下，0.60 s 后才出刺")
	room.player.position.x = 670
	tracking._time = 0.70
	tracking.queue_redraw()
	await snapshot("06_tracking_evade", "玩家走开 → 原位置破土 · 预警不追着角色移动")

	clear_concept()
	room.player.position.x = 440
	xs.clear(); warnings.clear(); eruptions.clear(); heights.clear()
	for x in range(120, 2461, 44):
		xs.append(float(x)); warnings.append(0.0); eruptions.append(1.0); heights.append(112)
	var tide := roots_at(xs, warnings, eruptions, heights, 0.72)
	await snapshot("07_tide_warning", "终击 · 整片地面预警 1.00 s，准备后闪")
	tide._time = 1.10
	tide.queue_redraw()
	await snapshot("08_tide_erupt", "全场根潮一次上冲 · 短伤害脉冲结束后，残根不补伤害")

	clear_concept()
	var ghost := Sprite2D.new()
	var player_sprite: AnimatedSprite2D = room.player.animated_sprite
	ghost.texture = player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, player_sprite.frame)
	ghost.position = Vector2(650, 555) + player_sprite.position
	ghost.scale = player_sprite.scale
	ghost.offset = player_sprite.offset
	ghost.flip_h = player_sprite.flip_h
	ghost.modulate = Color(0.65, 0.91, 1, 0.75)
	ghost.z_index = 14
	room.specimen.add_child(ghost)
	roots_at([586.0,618.0,650.0,682.0,714.0], [0.0,0.0,0.0,0.0,0.0], [1.0,1.0,1.0,1.0,1.0], [38,76,112,76,38], 1.10)
	room.player.position.x = 380
	await snapshot("09_decoy_cluster", "Q 雾分身破解 · 根潮聚向诱饵，玩家保持移动自由")
	overlay.return_path = PackedVector2Array([Vector2(650,558),Vector2(730,568),Vector2(810,564),Vector2(900,558),Vector2(980,555)])
	deer._show_clip(&"hurt_ING", 0)
	await snapshot("10_backlash", "地下力量回抽至鹿蹄下 → 4.5 s 失衡 · 不套藤笼")

	assert(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists)
	assert(not exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before)
	current_scene = null
	room.free()
	print("ROOT DESIGN: 10 screenshots; actual 12/12/20 combo sampled; save unchanged")
	quit()
