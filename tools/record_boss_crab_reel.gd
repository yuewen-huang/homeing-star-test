extends "record_crystal_crab_parry.gd"
var native_center := Vector2.ZERO
var native_side := -1.0
var extra_started := false
var filming_bullet := false
var bullet_ticks := 0
var bullet_hits := 0
var bullet_evades := 0

func _contact(target: Node, result: CombatHitResult.Type) -> void:
	if not extra_started:
		super._contact(target, result)
		events[-1]["frame"] = Engine.get_process_frames()
		return
	if result != CombatHitResult.Type.EVADED: failed = true
	events.append({"event":"bullet_contact","result":CombatHitResult.Type.keys()[result],"frame":Engine.get_process_frames(),"hp":lan.combat_stats.health})

func _finish() -> void:
	if extra_started:
		super._finish()
		return
	extra_started = true
	running = false
	_bullet_run.call_deferred()

func _bullet_run() -> void:
	Input.action_release(&"parry")
	crab.start_idle()
	if crab.poise_broken: crab.finish_stagger()
	crab.red_parry_hold = false
	crab._parry_pause = 0
	crab.combat_stats.restore_health()
	crab.combat_stats.restore_poise()
	crab.position = native_center
	lan.reset_after_map_fall(native_center + Vector2(native_side * 80, 0))
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.facing_direction = -native_side
	lan.apply_facing_direction()
	lan.parry_chain.cancel()
	lan.dodge_evaded_attack.connect(func(_source, _duration):
		bullet_evades += 1
		events.append({"event":"bullet_time_started","frame":Engine.get_process_frames()}))
	caption.text = "晶蟹 · 闪避震地 · 子弹时间追击"
	pressed.clear()
	crab.start_quake(&"double",lan.position)
	filming_bullet = true
	for i in 420: await physics_frame
	filming_bullet = false
	Input.action_release(&"ui_right")
	Input.action_release(&"ui_left")
	_key(KEY_J,false)
	_key(KEY_L,false)
	if bullet_hits == 0 or bullet_evades == 0: failed = true
	print("CRAB BULLET TIME: ",bullet_evades," evades, ",bullet_hits," attack frames")
	_finish()

func _physics_process(delta: float) -> bool:
	if not filming_bullet: return super._physics_process(delta)
	_key(KEY_J,false)
	_key(KEY_L,false)
	bullet_ticks += 1
	if lan.dodge_bullet_time_remaining > 0:
		var gap := crab.position.x-lan.position.x
		Input.action_release(&"ui_left" if gap > 0 else &"ui_right")
		Input.action_press(&"ui_right" if gap > 0 else &"ui_left")
		if bullet_ticks % 10 == 0: _key(KEY_J,true)
		if lan.attack_state != LanPlayer.AttackState.NONE:
			bullet_hits += 1
			if bullet_hits == 1: events.append({"event":"bullet_time_attack","frame":Engine.get_process_frames()})
	elif crab.rhythm != null:
		for i in crab.quake_beats.size():
			var beat := crab.quake_beats[i]
			var left: float = float(beat.t)-crab.quake_time
			if not beat.opened and left >= 0 and left <= 0.045 and not pressed.has(i):
				pressed[i] = true
				_key(KEY_L,true)
	return false

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
	assist._invincibility_label.hide()
	assist._difficulty_label.hide()
	load("D:/HomingStar/homeing-star-test/tools/recording_audio_mix.gd").apply(self)
	var field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field)
	current_scene = field
	await process_frame
	await process_frame
	field.target = int(field.state.boss_pile)
	field.feet = SaltFieldPerimeter.clamp_walker(field.piles[field.target].ground_position + Vector2(-200, 0))
	field._sync_view(0)
	field._finish_dig()
	while field.crab_encounter.entering: await physics_frame
	crab = field.crab_encounter.crab
	lan = field.pawn.player
	crab.manual_control = true
	native_center = field.crab_encounter.center
	native_side = -1.0 if native_center.x - crab.world_min_x > 200 else 1.0
	field.status.hide()
	crab.attack_hitbox.hit_resolved.connect(_contact)
	var layer := CanvasLayer.new()
	field.add_child(layer)
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
	crab.combat_stats.restore_poise_to(120)
	crab.position = native_center
	lan.reset_after_map_fall(native_center + Vector2(native_side * 80, 0))
	lan.velocity = Vector2.ZERO
	lan.parry_chain.cancel()
	lan.facing_direction = -native_side
	lan.apply_facing_direction()
	pressed.clear()
	caption.text = CAPTIONS[index]
	crab.start_quake(SEQUENCES[index],lan.position)
	contacts = 0
	idle = 0
	events.append({"event":"start","combo":SEQUENCES[index],"t":clock,"frame":Engine.get_process_frames(),"map":"res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn","boss_position":str(native_center)})
