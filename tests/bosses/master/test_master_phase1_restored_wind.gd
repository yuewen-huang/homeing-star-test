extends SceneTree

class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room
var master
var player: LanPlayer
var failures := 0
var checks := 0
var caption: Label
var output := "D:/HomingStar/.artifacts/master-restored-wind"
var outcomes: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func pose(action: StringName, at: float, facing := -1.0) -> void:
	master.position = Vector2(220,555)
	master.movement_direction = facing
	master.pending_drink = false
	master.red_parry_hold = false
	master.parry_pause_remaining = 0.0
	master._start_attack(action)
	master.combat_timeline.advance(at)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	caption.text = "师傅一阶段 · 旧手绘特效恢复\n%s / 本体 F%02d · 特效 F%02d" % [label,master.animated_sprite.frame,master.wind_effect.frame]
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	var previous := root.get_node("SaveProgress")
	root.remove_child(previous)
	previous.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	master = room.boss
	player = room.player
	master.set_process(false)
	master.set_physics_process(false)
	player.set_physics_process(false)
	player.position = Vector2(88,555)
	master.attack_hitbox.set_physics_process(false)
	master.combat_timeline.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	master.combat_timeline.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	var layer := CanvasLayer.new()
	layer.layer = 80
	room.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(20,606)
	layer.add_child(caption)
	check(FileAccess.get_file_as_bytes("res://assets/bosses/master/body/boss/master_combat_timelines.tres") == FileAccess.get_file_as_bytes("D:/HomingStar/homeing-star-test/fixtures/master/phase1_legacy_timelines.tres"),"Original authored timing and hitbox data restored byte-for-byte")
	for action: StringName in master.PHASE_1_WIND:
		var spec: Array = master.PHASE_1_WIND[action]
		var source: Texture2D = spec[0]
		var size: Vector2i = spec[1]
		var cols := source.get_width()/size.x
		for frame in int(spec[2]):
			pose(action,frame*0.1+0.001)
			var atlas := master.wind_effect.sprite_frames.get_frame_texture(action,frame) as AtlasTexture
			check(atlas.atlas == source and atlas.region == Rect2((frame%cols)*size.x,floori(frame/float(cols))*size.y,size.x,size.y),"%s F%02d uses the original painted source cell" % [action,frame])
			check(master.animated_sprite.frame == frame and master.wind_effect.frame == frame,"Body and painted wind share original frame timing")
		check(master.wind_effect.self_modulate.a == 1.0,"Original painted wind is visible")
		check(master.get_children().filter(func(node): return node is PixelSlash).is_empty(),"Rejected generic crescent does not overlay the painted wind")
		for sample in [[0.701,"warning"],[0.801,"active"],[float(spec[2])*0.1-0.099,"recovery"]]:
			pose(action,sample[0])
			await capture(String(action)+"_"+String(sample[1]))
	for action in [&"attack_1",&"attack_2"]:
		for frame in [8,9,10]:
			pose(action,frame*0.1+0.001)
			check(master.wind_effect.sprite_frames.get_frame_texture(action,frame).get_image().get_used_rect().has_area(),"Favourite painted opening frame remains intact")
			await capture("%s_favourite_F%02d" % [action,frame])
		pose(action,0.801,1.0)
		check(master.wind_effect.scale.x > 0,"Painted wind mirrors with right-facing body")
		await capture(String(action)+"_right")
	pose(&"attack_1",0.801)
	var frozen: float = master.combat_timeline.current_animation_position
	master.start_parry_feedback()
	master._process(0.03)
	check(not master.combat_timeline.is_playing() and is_equal_approx(master.combat_timeline.current_animation_position,frozen),"Parry pause holds painted wind on the body frame")
	master._interrupt_for_special(0.1)
	check(not master.wind_effect.visible and master.attack_hitbox.attack == null,"Interrupt clears painted wind and hitbox")
	master.play_phase_1_art_preview(&"air_spin_slam")
	check(not master.combat_timeline.is_playing() and master.attack_hitbox.attack == null and not master.wind_effect.visible,"New air move is an unarmed source preview pending design approval")
	# Actual overlapping hitbox -> real Lan guard -> shared contact settlement.
	pose(&"attack_1",0.801)
	master.parry_pause_remaining = 0.0
	player.start_parry()
	player.animated_sprite.frame = 3
	player.on_player_animation_frame_changed()
	player.animated_sprite.pause()
	master.attack_hitbox.hit_resolved.connect(func(target: Node,result: int) -> void:
		if target == player: outcomes.append(result))
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()
	await physics_frame
	await physics_frame
	await process_frame
	master.attack_hitbox._physics_process(0)
	check(outcomes.has(CombatHitResult.Type.PARRY_SUCCESS),"Restored attack resolves a real parry in the formal master room")
	check(get_nodes_in_group(CombatImpactEffect.GROUP).size() == 1,"Restored painted swing still uses one shared contact impact")
	await capture("restored_real_parry")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists,"Save existence unchanged")
	if exists: check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before,"Memory fixture leaves user progress byte-identical")
	Engine.time_scale = 1.0
	print("RESTORED MASTER WIND: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
