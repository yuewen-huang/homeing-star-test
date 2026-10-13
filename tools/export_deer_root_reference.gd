extends SceneTree
# Root effects are design references only; body actions use the real dev-room deer.
class LayerRoots extends RootSpikeVolley:
	var warning_only := false
	func _draw_warning_ring(spike: Dictionary) -> void:
		if not warning_only or _time < spike.warn_at or _time >= spike.erupt_at: return
		var progress: float = (_time - spike.warn_at) / (spike.erupt_at - spike.warn_at)
		var center := Vector2(spike.x, ground_y - 2)
		_draw_pixel_ellipse(center, spike.width + 8, 7, Color(0.85,0.68,0.25,0.25), true)
		_draw_pixel_ellipse(center, (spike.width + 8) * lerpf(2.2,1,progress), 7, Color("d9ad52"), false)
	func _draw() -> void:
		if warning_only:
			for spike in _spikes: _draw_warning_ring(spike)
		else: super._draw()

class Mound extends Node2D:
	var growth := 0.0
	var pulse := 0.0
	func _draw() -> void:
		if growth <= 0: return
		var points := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24
			points.append(Vector2(-44 + 88*t, -sin(t*PI)*52*growth))
		points.append(Vector2(44,0)); points.append(Vector2(-44,0))
		draw_colored_polygon(points, Color("789151"))
		draw_polyline(points, Color("bfd17d"), 4)

class ReturnFlow extends Node2D:
	var start := Vector2.ZERO
	var end := Vector2.ZERO
	var amount := 0.0
	func _draw() -> void:
		if amount <= 0 or amount >= 1: return
		var head := start.lerp(end, amount)
		var tail := start.lerp(end, maxf(0,amount-0.28))
		draw_line(tail, head, Color("b8c478"), 7)
		for i in 4:
			var q := start.lerp(end, clampf(amount-i*0.05,0,1))
			draw_line(q+Vector2(-7,3),q+Vector2(7,-3),Color("dfda91"),3)

var room
var deer: DeerBoss
var viewport: SubViewport
var body: Sprite2D
var ghost: Sprite2D
var flow: ReturnFlow
var roots: Array[LayerRoots] = []
var mounds: Array[Mound] = []
var clips: Array[Dictionary] = []
var seen := {}
var elapsed := 0.0
var output := ""
var canvas := Vector2i(512,384)
var anchor := Vector2(256,332)
var kind := ""
var q_time := 2.35

func _initialize() -> void: call_deferred("run")
func clear_effects() -> void:
	for node in roots: node.free()
	for node in mounds: node.free()
	roots.clear(); mounds.clear(); seen.clear()
	flow.amount = 0
	ghost.hide()

func add_roots(xs: Array, warnings: Array, eruptions: Array, heights: Array) -> void:
	var node := LayerRoots.new()
	node.setup(555, room.player.get_node("Hurtbox") as CombatHurtbox2D, deer, CombatAttackData.new(&"root_art_only",deer,0,0,0,0,CombatAttackData.DangerType.UNPARRYABLE_DANGER))
	node._rng.seed = 20261010
	node.hit_target = true
	for i in xs.size(): node.add_spike(xs[i], warnings[i], eruptions[i], heights[i])
	viewport.add_child(node)
	node.set_process(false)
	roots.append(node)

func sample_contact() -> void:
	if deer.attack_hitbox.attack == null: return
	var attack: CombatAttackData = deer.attack_hitbox.attack
	if seen.has(attack.get_instance_id()): return
	seen[attack.get_instance_id()] = elapsed
	if String(attack.attack_id).begins_with("deer_hoof_"):
		var mound := Mound.new()
		mound.position = deer.position + Vector2(deer._anchor_offset(&"light_ING",1,"hoof").x,0)
		mound.set_meta("start",elapsed)
		viewport.add_child(mound)
		mounds.append(mound)
	elif String(attack.attack_id).begins_with("deer_heavy_"):
		var xs: Array = []; var warnings: Array = []; var eruptions: Array = []; var heights: Array = []
		var hoof := deer.position.x + deer._anchor_offset(&"heavy_ING",0,"hoof").x
		for i in 8:
			xs.append(hoof + deer.direction*(120+i*64))
			warnings.append(elapsed+0.04+i*0.09)
			eruptions.append(elapsed+0.46+i*0.09)
			heights.append(36)
		add_roots(xs,warnings,eruptions,heights)

func advance() -> void:
	elapsed += 1.0/60
	if kind in ["light_nodule","heavy_wave","root_combo"]:
		deer._physics_process(1.0/60)
		sample_contact()

func pose_and_effects() -> String:
	var label := ""
	if kind in ["light_nodule","heavy_wave","root_combo"]:
		label = "抬蹄与蓄势" if seen.is_empty() else "破土与收招"
		if deer.state == DeerBoss.State.HEAVY and deer._segment < 0: label = "人立蓄势"
		if deer.combo_step >= 0: label = "第%d击_" % (deer.combo_step+1) + label
		if kind == "light_nodule" and elapsed > 1: label = "根瘤保持" if elapsed < 6.58 else "根瘤退回地下"
	elif kind == "tracking_module":
		deer._show_clip(&"roar_ING", 4)
		label = "锁定脚下预警" if elapsed < 0.6 else ("根刺上冲" if elapsed < 0.69 else ("根刺保持" if elapsed < 1.24 else "碎裂退回"))
	else:
		if elapsed < 1.2:
			deer._show_clip(&"roar_ING", mini(int(elapsed*6),7))
			label = "鹿鸣吟唱"
		elif elapsed < 6.35:
			deer._show_clip(&"roar_ING", 4+int(elapsed*4)%4)
			label = "六轮锁定与破土"
		elif elapsed < 7.2:
			deer._show_clip(&"roar_ING",7)
			label = "根力汇集"
		elif elapsed < 8.2:
			deer._show_clip(&"roar_ING",7)
			label = "终击地面预警"
		elif elapsed < 8.85:
			deer._show_clip(&"roar_ING",7)
			label = "全场根潮" if kind == "root_ultimate" else "根潮聚向分身"
		else:
			if kind == "decoy_counter":
				var hurt_time := elapsed - 8.85
				if hurt_time < 4.0/12.0: deer._show_clip_at(&"hurt_START",hurt_time)
				elif hurt_time < 1.0: deer._show_clip_at(&"hurt_ING",hurt_time-4.0/12.0)
				else: deer._show_clip_at(&"hurt_END",hurt_time-1.0)
				label = "失衡保持"
			else:
				deer._show_clip_at(&"idle_ING",elapsed-8.85,8.0,true)
				label = "喘息收招"
		if kind == "decoy_counter":
			ghost.visible = elapsed >= q_time and elapsed < 8.85
			if elapsed >= q_time and elapsed < q_time+0.25: label = "Q雾分身成形"
			flow.amount = clampf((elapsed-8.50)/0.35,0,1)
	flow.queue_redraw()
	for node in roots:
		node._time = elapsed
		if node.has_meta("redirect_from"):
			var center: float = node.get_meta("redirect_from") if elapsed < q_time else 900.0
			for i in node._spikes.size(): node._spikes[i].x = center + (i-1)*32
		node.queue_redraw()
	for mound in mounds:
		var age: float = elapsed - mound.get_meta("start")
		mound.growth = clampf(age/0.12,0,1) * clampf((6.24-age)/0.24,0,1)
		mound.queue_redraw()
	return label

func capture(folder: String, index: int) -> void:
	body.texture = deer.animated_sprite.sprite_frames.get_frame_texture(deer.animated_sprite.animation,deer.animated_sprite.frame)
	body.position = deer.position+deer.animated_sprite.position
	body.scale = deer.animated_sprite.scale
	body.flip_h = deer.animated_sprite.flip_h
	viewport.canvas_transform = Transform2D(0,Vector2.ONE/1.4,0,anchor-deer.position/1.4)
	var ghost_on := ghost.visible
	for layer in ["body","back","front","warning"]:
		body.visible = layer == "body"
		ghost.visible = ghost_on and layer == "body"
		flow.visible = layer == "back"
		for mound in mounds: mound.visible = layer == "front"
		for node in roots:
			node.visible = layer in ["front","warning"]
			node.warning_only = layer == "warning"
			node.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().save_png(folder.path_join("%04d_%s.png" % [index,layer])) == OK)
	ghost.visible = ghost_on

func export_clip(id: String, name: String, duration: float, width: int, pivot_x: int, action := -1) -> void:
	clear_effects()
	kind = id; elapsed = 0
	canvas = Vector2i(width,384); anchor = Vector2(pivot_x,332)
	viewport.size = canvas
	if action >= 0:
		if id == "root_combo": room.adapter.select_combo(1)
		room.play_action(action)
		deer._physics_process(0.000001)
	else:
		deer.position = Vector2(900 if id == "tracking_module" else 2200,555)
		deer.direction = -1
		deer._show_clip(&"roar_ING",0)
		if id == "tracking_module":
			add_roots([618.0,650.0,682.0],[0.0,0.0,0.0],[0.6,0.6,0.6],[38,45,38])
		else:
			var times: Array = [1.2,2.2,3.1,3.9,4.6,5.2]
			var positions: Array = [550.0,800.0,1050.0,1300.0,1550.0,1800.0]
			for i in 6:
				var x: float = positions[i]
				add_roots([x-32,x,x+32],[times[i],times[i],times[i]],[times[i]+0.6,times[i]+0.6,times[i]+0.6],[38,45,38])
				if id == "decoy_counter" and times[i]+0.6 >= q_time: roots[-1].set_meta("redirect_from",x)
			var xs: Array = []; var warnings: Array = []; var eruptions: Array = []; var heights: Array = []
			if id == "decoy_counter":
				for i in 5:
					xs.append(804+i*48); warnings.append(7.2); eruptions.append(8.2); heights.append([38,76,112,76,38][i])
				var sprite: AnimatedSprite2D = room.player.animated_sprite
				ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
				ghost.position = Vector2(900,555)+sprite.position
				ghost.scale = sprite.scale; ghost.offset = sprite.offset
				ghost.modulate = Color(0.65,0.91,1,0.75)
				flow.start = Vector2(900,560); flow.end = Vector2(2200,560)
			else:
				for x in range(120,2461,44):
					xs.append(x); warnings.append(7.2); eruptions.append(8.2); heights.append(112)
			add_roots(xs,warnings,eruptions,heights)
	var folder := output.path_join("raw").path_join(id)
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	for index in ceili(duration*20):
		var label := pose_and_effects()
		frames.append({"index":index,"time_ms":index*50,"duration_ms":50,"stage":label,
			"animation":String(deer.animated_sprite.animation),"body_frame":deer.animated_sprite.frame,
			"world_position":[deer.position.x,deer.position.y],"direction":deer.direction,
			"attack":String(deer.attack_hitbox.attack.attack_id) if action >= 0 and deer.attack_hitbox.attack != null else "",
			"concept_only":true})
		await capture(folder,index)
		for i in 3: advance()
	clips.append({"id":id,"name":name,"folder":folder,"canvas":[canvas.x,canvas.y],"anchor":[anchor.x,anchor.y],"frames":frames})
	print("EXPORTED ",id," ",frames.size()," frames")

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	deer = room.adapter.boss as DeerBoss
	deer.set_physics_process(false); deer.vfx.set_process(false)
	room.player.set_physics_process(false); room.set_physics_process(false); room.set_process(false)
	room.hide()
	viewport = SubViewport.new(); viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	body = Sprite2D.new(); body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; viewport.add_child(body)
	ghost = Sprite2D.new(); ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; viewport.add_child(ghost)
	flow = ReturnFlow.new(); viewport.add_child(flow)
	var mode := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "all"
	if mode != "counter_only":
		await export_clip("light_nodule","01_轻跺与根瘤",7.0,512,256,0)
		await export_clip("heavy_wave","02_重踩连续根浪",4.0,1024,768,1)
		await export_clip("root_combo","03_根阶段快快慢",5.5,1024,768,2)
	if mode == "all":
		await export_clip("tracking_module","04_追踪破土模块",2.0,512,256)
		await export_clip("root_ultimate","05_全场根潮大招",10.35,2048,1740)
	if mode != "normal_only":
		await export_clip("decoy_counter","06_雾分身破解与反噬",13.35,2048,1740)
	if OS.get_cmdline_user_args().size() > 1:
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("capture_manifest.json")))
		var revised: Array[Dictionary] = []
		for clip in previous.clips:
			if not clips.any(func(updated: Dictionary) -> bool: return updated.id == clip.id): revised.append(clip)
		revised.append_array(clips); clips = revised
	var file := FileAccess.open(output.path_join("capture_manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"design_proposal_not_runtime_implementation","fps":20,"world_units_per_pixel":1.4,"source_scene":"res://scenes/dev/boss_development_room.tscn","clips":clips},"\t")); file.close()
	assert(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == existed)
	assert(not existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved)
	viewport.free(); current_scene = null; room.free()
	print("ROOT ART COMPLETE; save unchanged; no AI; no damage")
	quit()
