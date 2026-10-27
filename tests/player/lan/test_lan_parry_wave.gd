extends "../../support/harness.gd"

class Attacker extends DamageReceiver2D:
	var damage := 0
	func receive_hit(amount: int, _source: Vector2) -> void: damage+=amount

var player: LanPlayer
var source: Attacker
var hitbox: CombatHitbox2D
var visual: LanClashVisual
var serial := 0

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or not OS.get_cmdline_user_args().has("--capture"): return
	await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func parry(red := false) -> Node2D:
	serial+=1
	# Samples are manually stepped; retire the previous atlas contact before the
	# next forced input so an unscaled test loop cannot pile up frozen impacts.
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()
	player.start_parry()
	var hit := CombatAttackData.new(StringName("wave_%d" % serial),source,12,10,180,0,
		CombatAttackData.DangerType.COUNTERABLE_DANGER if red else CombatAttackData.DangerType.NORMAL)
	var before := get_nodes_in_group(CombatImpactEffect.GROUP).size()
	var result: CombatHitResult.Type=player.hurtbox.receive_attack(hit)
	hitbox._complete_hit(player,player.hurtbox.global_position,hit,result)
	player.animated_sprite.pause()
	check(result==CombatHitResult.Type.PARRY_SUCCESS,"Real guard settlement succeeds")
	check(get_nodes_in_group(CombatImpactEffect.GROUP).size()==before+1,"One shared contact impact, with no second burst")
	return visual.parry_waves[-1]

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var room := Node2D.new()
	root.add_child(room)
	current_scene=room
	var backdrop := Node2D.new()
	backdrop.z_index=-10
	backdrop.draw.connect(func() -> void:
		for x in 20:
			for y in 12:
				backdrop.draw_rect(Rect2(x*64,y*64,64,64),Color("26323d") if (x+y)%2==0 else Color("354551")))
	room.add_child(backdrop)
	var camera := Camera2D.new()
	room.add_child(camera)
	camera.position=Vector2(640,360)
	camera.make_current()
	player=load("res://scenes/player/lan/lan_player.tscn").instantiate()
	player.position=Vector2(600,555)
	player.world_min_x=0
	player.world_max_x=2000
	room.add_child(player)
	player.set_physics_process(false)
	visual=player.clash_visual
	visual.set_process(false)
	source=Attacker.new()
	room.add_child(source)
	source.position=Vector2(780,555)
	hitbox=CombatHitbox2D.new()
	room.add_child(hitbox)
	hitbox.set_physics_process(false)
	await process_frame
	var sizes: Array[float]=[]
	for count in range(1,7):
		var wave := parry()
		check(int(wave.level)==mini(count,5),"Actual consecutive parries drive the capped wave level")
		check(wave.spec.sparks==0.0 and wave._sparks.is_empty(),"Imported wave adds no duplicate contact sparks")
		check(wave._vignette==null and wave.spec.chroma==0.0,"Ordinary wave adds no screen pulse or colour split")
		check(wave.global_position==player.global_position+Vector2(0,LanClashVisual.SWORD_ROOT.y),"Air lens surrounds Lan's guard-height body")
		check(wave.tilt>0,"Ring leans toward an attacker on the right")
		if count>=3: check(int(wave.spec.rings)>=2,"Consecutive parries add the authored extra rings")
		sizes.append(float(wave.spec.radius))
		var age: float=wave.age
		visual.advance(0)
		check(is_equal_approx(wave.age,age),"A held action clock holds the wave")
		visual.advance(.10)
		check(is_equal_approx(wave.age-age,.10),"Wave uses the same scaled clock as clash art")
		if count in [1,3,5]: await capture("parry_%d" % count)
	check(sizes[1]>sizes[0] and sizes[4]>sizes[3] and is_equal_approx(sizes[5],sizes[4]),"Ring escalation grows and then caps")
	check(visual.chain==6,"Existing clash counter is still the only run counter")
	visual.break_chain()
	check(visual.chain==6,"Taking a hit still does not reset the established clash run")
	source.position.x=450
	var left := parry()
	check(left.tilt<0,"Attacker on the left mirrors the authored tilt")
	var origin: Vector2=left.global_position
	player.position.x+=50
	check(left.global_position==origin,"A released lens stays at its original world contact")
	var red := parry(true)
	check(red.spec.red and red.spec.tint==red.RED_TINT and int(red.spec.rings)==3,"Real red guard produces the pull-and-three-ring red wave")
	check(red._vignette==null and red._sparks.is_empty(),"Red guard does not duplicate the global vignette or contact sparks")
	check((root.get_node("CombatFeedback") as CombatFeedbackService).screen_fx.pulse_active(),"Existing red screen pulse remains in charge")
	visual.advance(.12)
	await capture("red_parry")
	var from_x := player.global_position.x
	visual._on_red_frame(source,LanClashVisual.COUNTER_FRAME)
	check(player.global_position.x!=from_x and visual._pending.size()==4,"Red counter keeps its original crossing and three-cut schedule")
	visual.advance(.40)
	check(source.damage==3*CombatTuning.LAN_RED_COUNTER_HIT_DAMAGE,"Import preserves all three actual red-counter damage settlements")
	visual.advance(LanClashVisual.CHAIN_WINDOW+.1)
	check(visual.chain==0 and visual.parry_waves.is_empty(),"Timeout resets the run and releases finished waves")
	var fresh := parry()
	check(int(fresh.level)==1,"The next run restarts at the ordinary saved look")
	visual.set_process(true)
	paused=true
	var held: float=fresh.age
	await process_frame
	await process_frame
	check(is_equal_approx(fresh.age,held),"Pausing the game freezes the new lens")
	paused=false
	visual.set_process(false)
	if DisplayServer.get_name()!="headless":
		for age in [.08,.16,.26]:
			visual.advance(age-float(fresh.age))
			await process_frame
			await RenderingServer.frame_post_draw
		check(true,"Actual GPU renders the imported refraction lens")
	player.reset_after_map_fall(Vector2(600,555))
	check(visual.parry_waves.is_empty() and not is_instance_valid(fresh),"Retry clears the owned waves immediately")
	parry()
	player.combat_stats.health=0
	visual.advance(.01)
	check(visual.parry_waves.is_empty(),"Defeat clears outstanding parry waves")
	room.free()
	current_scene=null
	await process_frame
	check(get_nodes_in_group(LanClashVisual.PARRY_WAVE_GROUP).is_empty(),"Player teardown leaves no world lens behind")
	expect_save_untouched()
	finish("LAN STUDIO PARRY WAVES")
