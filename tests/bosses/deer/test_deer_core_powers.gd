extends "../../support/harness.gd"
const Spell = preload("res://scripts/bosses/deer/deer_wind_spell.gd")
var room: Chapter1DeerBossRoom
var lan: LanPlayer
var boss: Node2D
var power: Node2D
var save: MemoryProgress

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func phase(number: int) -> void:
	room.encounter._spawn_phase(number,1450)
	boss = room.encounter.actor
	power = boss.core_powers
	boss.wait_left = 999
	boss.selected_exercise = 0
	await wait_frames(2) # Production VFX audio/painted nodes initialize deferred.
	if number==4:
		boss.transform_left = 0
		boss.invulnerable = false
	lan.reset_after_map_fall(Vector2(1280,555))
	lan.combat_stats.restore_health()
	lan.set_physics_process(false)
	room.encounter.core_power_state.cooldown = 0.0
	power.refresh_hud()

func q() -> void:
	Input.action_press(&"special_item_use")
	var id := lan.read_special_item_input()
	if id!=&"": lan.special_item_use_requested.emit(id)
	Input.action_release(&"special_item_use")

func run() -> void:
	save = use_memory_progress()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(3)
	lan=room.player
	await phase(1)
	check(not power.use_power() and power.cooldown()==0,"Locked core cannot cast or spend cooldown")
	save.claim_unique_reward(ForestCoreRelic.REWARD_ID,ItemCatalog.SPIRIT_PENDANT)
	save.try_complete_fact(ForestCoreRelic.power_id(1))
	lan.air_state=LanPlayer.AirState.FALLING
	check(not power.use_power() and power.cooldown()==0,"Airborne planting does not spend cooldown")
	lan.air_state=LanPlayer.AirState.GROUNDED
	q()
	check(power.effect_phase==1 and power.cooldown()==20,"Production Q input casts the unlocked phase power and starts 20s immediately")
	check(not power.use_power(),"Repeated Q cannot bypass shared cooldown")
	paused=true
	check(not power.use_power() and power.cooldown()==20,"Paused game cannot cast or spend additional cooldown")
	paused=false
	power.advance(.2)
	lan.position.x=1150
	await capture("core_1_trip_placed")
	lan.position.x=1280
	var left: float=power.cooldown()
	lan.input_frozen=true
	boss._physics_process(.25)
	check(power.cooldown()==left and power.effect_phase==1,"Cinematic input freeze preserves timer and placed effect")
	lan.input_frozen=false
	boss.action_clock.pause(1)
	boss._physics_process(.1)
	check(power.cooldown()==left,"Hit stop freezes action-clock cooldown")
	boss.action_clock.clear()
	lan.ultimate_active=true
	boss._physics_process(.1)
	check(is_equal_approx(power.cooldown(),left-.1),"Lan ultimate speed does not accelerate core cooldown")
	lan.ultimate_active=false
	check(not power.trip_rush(1000,1100,555) and not power.trip_rush(1100,1400,450),"A miss or wrong-height sweep cannot trigger the planted vine")
	# Run the production rush across the actual placed point; preserve the next phrase.
	boss.position=Vector2(1000,555)
	boss._starting_pressure_move=true
	boss.start_move(0,1400)
	boss._starting_pressure_move=false
	boss.pressure.active=true
	boss.pressure.phrase=0
	boss.pressure.step=0
	boss.age=boss.RUSH_PREP+boss._rush_duration*.8
	boss._duel_rush()
	check(power.triggered and is_equal_approx(boss.position.x,1280),"Only real swept rush crossing trips at the vine")
	check(boss.pressure.active and boss.pressure.step==1 and boss.opening==0 and boss.defense_credit==0,"Trip keeps the next combo, grants no beads or long weak state")
	boss.cancel_duel()
	room.encounter.core_power_state.cooldown=0.0
	check(power.use_power(),"Second setup can place after reset")
	power.advance(5)
	check(power.effect_phase==0 and power.cooldown()==15,"An unused 5s vine expires with 15s cooldown remaining")
	room.encounter.core_power_state.cooldown=0
	power.use_power()
	boss.combat_stats.apply_health_damage(boss.combat_stats.health)
	room.encounter._physics_process(.5)
	check(power.effect_phase==0 and power.cooldown()==20,"Phase handoff clears active power and freezes cooldown")
	room.encounter._physics_process(2.0)
	boss=room.deer
	power=boss.core_powers
	check(room.encounter.phase==2 and power.cooldown()==20,"Next actor inherits remaining shared cooldown")
	check(not power.unlocked(),"Vine unlock does not grant the mist power")

	await phase(2)
	save.try_complete_fact(ForestCoreRelic.power_id(2))
	boss.root_exercise=1
	lan.position.x=1100
	boss.start_move(1,1450)
	var old_aim: float=boss._aim
	q()
	check(power.effect_phase==2 and boss._aim==old_aim,"Casting a decoy never changes an existing attack lock")
	lan.position.x=1280
	await capture("core_2_decoy")
	boss.start_move(1,1500)
	check(boss._aim==1100 and power.effect_phase==0,"Next new lock consumes the decoy's fixed position")
	boss.start_move(1,1500)
	check(boss._aim==1500,"Following attacks resume their normal target")
	boss.cancel_duel()
	room.encounter.core_power_state.cooldown=0
	power.use_power()
	power.advance(3)
	boss.start_move(1,1500)
	check(boss._aim==1500 and power.cooldown()==17,"Expired decoy attracts nothing and retains spent cooldown")

	await phase(3)
	save.try_complete_fact(ForestCoreRelic.power_id(0))
	lan.facing_direction=1
	boss.arena.begin(1)
	boss.arena._add(1380,false,330,0)
	boss.arena.hazards.back()["reveal"]=0.0
	boss.arena._add(1580,false,330,0)
	boss.arena.hazards.back()["reveal"]=0.0
	boss.arena.advance(.02)
	var inside: Dictionary=boss.arena.hazards[0]
	var outside: Dictionary=boss.arena.hazards[1]
	q()
	check(inside.get("cleared_by_wind",false) and inside.contact.hitbox.attack==null,"Wind immediately disables an existing thorn in the corridor")
	boss.arena.advance(.02)
	check(not outside.get("cleared_by_wind",false) and outside.contact.hitbox.attack!=null,"Thorn outside the 200px corridor remains dangerous")
	lan.position.x=1380
	var health_before := lan.combat_stats.health
	inside.contact.resolve()
	check(lan.combat_stats.health==health_before,"Real Lan hurtbox takes no damage crossing a suppressed thorn")
	lan.position.x=1580
	outside.contact.resolve()
	check(lan.combat_stats.health<health_before,"An unsuppressed thorn still damages the real Lan hurtbox")
	lan.reset_after_map_fall(Vector2(1280,555))
	lan.combat_stats.restore_health()
	power.advance(.2)
	power.advance(.12)
	await capture("core_3_corridor")
	# A late-emerging thorn is suppressed until its own natural expiry, even after wind ends.
	boss.arena._add(1400,false,330,.7)
	boss.arena.hazards.back()["reveal"]=0.0
	var late: Dictionary=boss.arena.hazards.back()
	power.advance(.7)
	boss.arena.advance(.71)
	check(late.get("cleared_by_wind",false),"Wind also catches thorns that emerge while the corridor is active")
	# Cross the expiry boundary even without the extra frame of a visual capture.
	power.advance(.19)
	boss.arena.advance(.1)
	check(power.effect_phase==0 and late.contact.hitbox.attack==null,"A suppressed thorn cannot rearm when wind expires")
	boss.start_move(2,lan.position.x)
	boss.age=boss.SWEEP_PREP+.1
	boss._duel_sweep()
	check(boss.attack_hitbox.attack!=null,"Core wind grants no immunity against body attacks")

	await phase(4)
	save.try_complete_fact(ForestCoreRelic.power_id(3))
	lan.position.x=880
	q()
	var spell: Node2D=Spell.new()
	spell.kind="tornado"
	spell.boss=boss
	spell.start=boss.global_position
	spell.aim=lan.position
	boss.add_child(spell)
	lan.position.x=1280
	var wall: Dictionary=spell.objects[0]
	var other: Dictionary=spell.objects[1]
	for i in 300:
		spell.advance(1.0/60)
		power.advance(1.0/60)
		if power.triggered: break
	check(power.triggered and wall.get("anchor_hold",0.0)>0 and other.get("anchor_hold",0.0)==0,"Only the wall that actually crosses the root is held")
	var stopped_x: float=spell.tornado_x(wall)
	var other_x: float=spell.tornado_x(other)
	for i in 30:
		spell.advance(1.0/60)
		power.advance(1.0/60)
	check(absf(spell.tornado_x(wall)-stopped_x)<.01 and spell.tornado_x(other)<other_x,"Held wall stays put while opposite wall continues")
	await capture("core_4_wall_held")
	for i in 40:
		spell.advance(1.0/60)
		power.advance(1.0/60)
	check(spell.tornado_x(wall)>stopped_x and absf(float(wall.anchor_delay)-1.0)<.02,"After one second wall resumes without jumping to the original timeline")
	check(power.effect_phase==0 and boss.defense_credit==0,"Root breaks after hold, granting no parry beads")
	spell.retire()
	room.encounter.core_power_state.cooldown=12.0
	boss.transform_left=2
	boss._physics_process(.5)
	check(power.cooldown()==12,"Human transformation freezes the inherited cooldown")
	boss.transform_left=0
	room.encounter.core_power_state.cooldown=0
	power.use_power()
	lan.combat_stats.apply_health_damage(lan.combat_stats.health)
	check(power.effect_phase==0,"Player death clears a placed root")
	lan.combat_stats.restore_health()
	room.encounter.restart()
	check(room.encounter.actor.core_powers.cooldown()==0 and room.encounter.phase==1,"Death retry restores first phase and ready shared cooldown")
	check(not save._config.encode_to_text().contains("cooldown"),"Runtime cooldown is never saved")
	room.encounter.stop()
	current_scene=null
	room.free()
	await wait_frames(2)
	# Development actors expose the same Q route without changing saved ownership.
	var facts_before := save._config.encode_to_text()
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(dev)
	current_scene=dev
	await wait_frames(2)
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if not BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_wind_duel_adapter.gd"): continue
		dev.select_boss(i)
		await wait_frames(2)
		power=dev.adapter.deer.core_powers
		check(power.preview_all_unlocked and not power.use_power(),"Manual development preview does not accept combat Q")
		dev.set_combat_simulation(true)
		lan=dev.player
		boss=dev.adapter.deer
		boss.transform_left=0
		boss.wait_left=999
		lan.reset_after_map_fall(Vector2(640,555))
		lan.set_physics_process(false)
		power.refresh_hud()
		q()
		check(power.effect_phase==4 and power.cooldown()==20,"Development combat uses the same fourth-phase Q and cooldown")
		await capture("core_development_q")
		break
	check(save._config.encode_to_text()==facts_before,"Development preview never writes core ownership or inventory")
	current_scene=null
	dev.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER CORE POWERS")
