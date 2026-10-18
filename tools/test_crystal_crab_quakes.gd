extends SceneTree
## Real production boss scripts and Lan receiver, in the existing production boss room.
## Development captures verify art only; they are not used to claim parry success.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var checks := 0
var failures := 0
var crab: CrystalCrabBoss
var lan: LanPlayer
var feedback: CombatFeedbackService
var results: Array[int] = []
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label_)

func reset_feedback() -> void:
	feedback.hit_stop_serial += 1
	Engine.time_scale = 1.0
	feedback.screen_fx.clear()
	feedback._reset_punch()
	feedback.shake_remaining = 0
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()
	if is_instance_valid(lan):
		for piece in lan.clash_visual.pieces:
			if is_instance_valid(piece): piece.free()
		lan.clash_visual.pieces.clear()
		lan.clash_visual.chain = 0
		lan.clash_visual.counter_view.hide_count()

func place() -> void:
	reset_feedback()
	crab.start_idle()
	if crab.poise_broken: crab.finish_stagger()
	crab.red_parry_hold = false
	crab._parry_pause = 0
	crab.combat_stats.restore_health()
	crab.combat_stats.restore_poise_to(120)
	crab.position = Vector2(820,555)
	lan.reset_after_map_fall(Vector2(900,555))
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	lan.clash_visual.break_chain()
	lan.defense_state = LanPlayer.DefenseState.NONE
	lan.velocity = Vector2.ZERO
	results.clear()

func tick(seconds: float, parry := false) -> void:
	for i in ceili(seconds*120):
		if parry: lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
		crab._physics_process(1.0/120)
		lan.combat_clock += 1.0/120

func capture(label_: String) -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label_+".png"))

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	feedback = root.get_node("CombatFeedback")
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	room.enable_deer_boss = false
	root.add_child(room)
	current_scene = room
	await process_frame
	lan = room.player
	lan.set_physics_process(false)
	crab = load("res://scenes/sideview/crystal_crab_boss.tscn").instantiate()
	crab.combat_target = lan
	crab.manual_control = true
	crab.position = Vector2(820,555)
	room.add_child(crab)
	crab.set_physics_process(false)
	crab.attack_hitbox.hit_resolved.connect(func(_target, result): results.append(result))
	for danger in [1,2]:
		crab.quake_vfx.cue(danger,0.10,crab.get_counter_slash_point())
		check(crab.quake_vfx.glint_pieces.size()==2 and crab.quake_vfx.glint_pieces.all(func(piece): return not piece._clip.is_empty()),"Red/gold warning uses the current baked star and converging shards %d" % danger)
		check(crab.quake_vfx.glint.global_position.distance_to(crab.get_counter_slash_point())<0.01,"Danger cue follows the current painted core %d" % danger)
	# Data validation: fitted body rates, unique VFX recipes, visible landing frames.
	for id in CrystalCrabQuakeRhythm.ORDER:
		var score := CrystalCrabQuakeRhythm.new(id)
		var rates_ok := true
		for i in range(1,score.keys.size()):
			var rate: float = float(score.keys[i][1]-score.keys[i-1][1])/float(score.keys[i][0]-score.keys[i-1][0])
			if rate>0: rates_ok = rates_ok and rate>=4 and rate<=40
		check(rates_ok,"VFX-first fitted frames stay within 4–40 fps: "+String(id))
		for beat in score.beats:
			var effect := PixelSlash.new().configure(score.effect_spec(beat.radius,beat.danger))
			room.add_child(effect)
			check(not effect._clip.is_empty(),"Production quake atlas is available: "+String(id))
			check(effect._clip.times.any(func(time): return is_equal_approx(float(time),CrystalCrabQuakeRhythm.OPEN)),"Baked quake contains the exact compression image held at contact: "+String(id))
			effect.free()
	place()
	crab.start_quake(&"left",lan.position)
	tick(0.70)
	check(crab.source_frame==8 and results.size()==1,"Left ground AOE lands at source F08 through the real hurtbox")
	var health := lan.combat_stats.health
	tick(0.50)
	check(results.size()==1 and lan.combat_stats.health==health,"A held AOE and its residue do not hit twice")
	place()
	lan.position.y -= 160
	crab.start_quake(&"left",lan.position)
	tick(1.4)
	check(results.is_empty(),"Jumping above the 64-pixel ground layer avoids the AOE")
	place()
	lan.position.x = 400
	crab.start_quake(&"left",lan.position)
	tick(1.4)
	check(results.is_empty(),"Leaving the warned ground footprint avoids damage")
	place()
	crab.start_quake(&"triple",lan.position)
	tick(1.80,true)
	check(results.size()==3 and results.all(func(r): return r==CombatHitResult.Type.PARRY_SUCCESS),"Hard difficulty parries three ground pulses through real Lan settlement")
	check(crab.combat_stats.poise==45,"Each ground parry removes 25 poise; the combo does not refill it")
	check(crab.quake_vfx.pieces.all(func(e): return e.shape==&"quake"),"Crab attacks contain only ground art, no slash crescents")
	place()
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	crab.start_quake(&"red",lan.position)
	tick(0.82,true)
	lan.defense_state = LanPlayer.DefenseState.NONE
	tick(2.0)
	check(results.size()==3 and results.all(func(r): return r==CombatHitResult.Type.PARRY_SUCCESS),"Normal difficulty continues the same quake chain automatically")
	check(not crab.red_parry_hold and not crab.poise_broken,"Automatically parried red quake does not earn PLUS")
	var old_key := crab.get_parry_chain_key()
	crab.start_quake(&"red",lan.position)
	check(crab.get_parry_chain_key()!=old_key and not lan.parry_chain.covers(crab,lan.combat_clock),"Replaying a rhythm creates a fresh chain key")
	place()
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	crab.start_quake(&"heavy",lan.position)
	tick(1.25,true)
	check(crab.red_parry_hold and crab.poise_broken and crab.rhythm==null,"Manual red quake parry interrupts the score and starts PLUS")
	check(crab.quake_vfx.last_impact==&"double" and crab.quake_vfx.impact_voices.any(func(voice): return voice.playing),"Parry stagger does not cut off the landed double-slam sound")
	place()
	crab.start_quake(&"gold",lan.position)
	# Evade the two initial waves geometrically, then try guarding the gold wave.
	lan.position.y -= 160
	tick(2.40)
	lan.position.y = 555
	lan.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	health = lan.combat_stats.health
	tick(0.14)
	check(results.size()==1 and results[0]==CombatHitResult.Type.NORMAL_HIT and lan.combat_stats.health==health-24,"Gold ground quake bypasses parry and half-damage guard")
	place()
	crab.start_quake(&"aftershock",lan.position)
	tick(2.82,true)
	check(results.size()==1 and crab.rhythm!=null,"Parrying the first burrow landing does not cancel its planned gold aftershock")
	crab.enter_stagger(3)
	tick(1.0)
	check(results.size()==1 and crab.attack_hitbox.attack==null and not crab.invulnerable,"Poise break cancels pending aftershock and clears underground immunity")
	place()
	crab.start_quake(&"aftershock",lan.position)
	lan.position.y -= 160
	tick(2.60)
	check(results.is_empty() and crab.source_frame<27,"Burrow travel and rising body do not cause contact damage")
	var at := crab.position
	crab.position.x += 20
	var center: Vector2 = crab.quake_beats[0].center
	check(is_equal_approx(center.x,at.x+20*crab.direction),"Locked ground centre is independent of later body movement")
	place()
	crab.start_quake(&"left",lan.position)
	tick(0.50)
	var frozen := crab.quake_time
	crab._parry_pause = 1
	crab._physics_process(0.10)
	check(is_equal_approx(crab.quake_time,frozen),"Hit-stop freezes body and quake score together")
	# Representative in-engine warning, active and recovery renders for all six scores.
	for id in CrystalCrabQuakeRhythm.ORDER:
		place()
		lan.position = Vector2(480,555)
		crab.start_quake(id,Vector2(820,555))
		var last: float = crab.quake_beats[-1].t
		tick(last-0.15)
		await capture(String(id)+"_warning")
		tick(0.15)
		await capture(String(id)+"_active")
		tick(0.18)
		await capture(String(id)+"_recovery")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	place()
	crab.start_quake(&"heavy",Vector2(820,555))
	tick(0.65)
	check(crab.quake_vfx.warning._suppressed and crab.quake_vfx.glint.visible,"Nightmare hides range marks but retains the danger glint")
	reset_feedback()
	room.free()
	current_scene = null
	await process_frame
	print("CRYSTAL CRAB QUAKES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
