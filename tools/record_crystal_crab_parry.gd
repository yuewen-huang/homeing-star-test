extends SceneTree
## Scripted button presses, hard difficulty, invincibility off. No forged hit results.
## Same production actor and Lan in the existing production room; no demo scene/resources.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

const SEQUENCES := [&"double",&"triple",&"red",&"gold",&"aftershock"]
const CAPTIONS := ["左右震地 · 连续格挡", "压地三叠震 · 三连格挡", "赤晶重震 · 红色反击", "金晶迟震 · 格挡后跃起", "潜盐余震 · 格挡后闪避"]
var crab: CrystalCrabBoss
var lan: LanPlayer
var caption: Label
var output := ""
var events: Array[Dictionary] = []
var running := false
var clock := 0.0
var idle := 0.0
var index := -1
var pressed := {}
var release_parry := false
var release_jump := false
var release_dodge := false
var contacts := 0
var failed := false

func _initialize() -> void: setup.call_deferred()

func setup() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"),-18.0)
	var room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	room.enable_deer_boss = false
	room.room_title = "晶蟹 · 砸地交锋"
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	lan = room.player
	crab = load("res://scenes/bosses/crystal_crab/crystal_crab_boss.tscn").instantiate()
	crab.combat_target = lan
	crab.manual_control = true
	crab.position = Vector2(920,555)
	room.add_child(crab)
	room._status.text = "困难 · 手动格挡 · 无敌关闭"
	crab.attack_hitbox.hit_resolved.connect(_contact)
	var layer := CanvasLayer.new()
	room.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(350,100)
	caption.size.x = 580
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size",26)
	caption.add_theme_color_override(&"font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override(&"shadow_offset_x",2)
	caption.add_theme_constant_override(&"shadow_offset_y",2)
	layer.add_child(caption)
	running = true
	_next()

func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func _next() -> void:
	index += 1
	if index>=SEQUENCES.size():
		_finish()
		return
	crab.start_idle()
	if crab.poise_broken: crab.finish_stagger()
	crab.red_parry_hold = false
	crab._parry_pause = 0
	crab.combat_stats.restore_health()
	crab.combat_stats.restore_poise()
	crab.position = Vector2(920,555)
	lan.reset_after_map_fall(Vector2(840,555))
	lan.velocity = Vector2.ZERO
	lan.parry_chain.cancel()
	lan.facing_direction = 1
	lan.apply_facing_direction()
	pressed.clear()
	caption.text = CAPTIONS[index]
	crab.start_quake(SEQUENCES[index],lan.position)
	contacts = 0
	idle = 0
	events.append({"event":"start","combo":SEQUENCES[index],"t":clock})

func _physics_process(delta: float) -> bool:
	if not running: return false
	clock += delta
	if release_parry: Input.action_release(&"parry"); release_parry = false
	if release_jump: Input.action_release(&"jump"); release_jump = false
	if release_dodge: _key(KEY_L,false); release_dodge = false
	if clock>45:
		failed = true
		_finish()
		return false
	if crab.rhythm != null:
		for i in crab.quake_beats.size():
			var beat := crab.quake_beats[i]
			var left: float = float(beat.t)-crab.quake_time
			if beat.opened or pressed.has(i) or left<0: continue
			if int(beat.danger)==2:
				if SEQUENCES[index]==&"aftershock" and left<=0.12:
					_key(KEY_L,true)
					release_dodge = true
					pressed[i] = true
					events.append({"event":"dodge","t":clock,"lead":left})
				elif SEQUENCES[index]!=&"aftershock" and left<=0.34:
					Input.action_press(&"jump")
					release_jump = true
					pressed[i] = true
					events.append({"event":"jump","t":clock,"lead":left})
			elif left<=0.20:
				Input.action_press(&"parry")
				release_parry = true
				pressed[i] = true
				events.append({"event":"parry_press","t":clock,"lead":left})
	else:
		if crab.poise_broken or lan.defense_state==LanPlayer.DefenseState.RED_PARRY_SUCCESS: return false
		idle += delta
		if idle>=1.0:
			var expected: int = [2,3,3,2,1][index]
			if contacts!=expected: failed = true
			events.append({"event":"end","combo":SEQUENCES[index],"parries":contacts,"expected":expected,"t":clock})
			_next()
	return false

func _contact(_target: Node, result: CombatHitResult.Type) -> void:
	if result==CombatHitResult.Type.PARRY_SUCCESS: contacts += 1
	elif result!=CombatHitResult.Type.EVADED: failed = true
	events.append({"event":"contact","result":CombatHitResult.Type.keys()[result],"combo":SEQUENCES[index],"t":clock,"hp":lan.combat_stats.health})
	var label_: String = "%s_%02d" % [SEQUENCES[index],contacts]
	RenderingServer.frame_post_draw.connect(func(): root.get_texture().get_image().save_png(output.path_join(label_+".png")),CONNECT_ONE_SHOT)

func _finish() -> void:
	running = false
	Input.action_release(&"parry")
	Input.action_release(&"jump")
	_key(KEY_L,false)
	FileAccess.open(output.path_join("events.json"),FileAccess.WRITE).store_string(JSON.stringify(events,"\t"))
	print("CRAB PARRY RECORDING: ","FAIL" if failed else "PASS",", ",events.size()," events, ",clock," seconds")
	quit(1 if failed else 0)
