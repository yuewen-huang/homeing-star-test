extends "../../support/harness.gd"
var room: Chapter1DeerBossRoom
var player: LanPlayer

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro:=WindSightingComic.new()
	var packed:=PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	player=room.player
	player.set_physics_process(false)
	var finisher:=LanAttackEffectCatalog.attack_3x(LanPlayer.ATTACK_3_FPS).attack_hit_context
	for phase in range(1,5):
		room.encounter._spawn_phase(phase,1420)
		room.encounter.start()
		var boss:=room.deer
		boss.manual_control=true
		boss.set_physics_process(false)
		boss.invulnerable=false
		player.reset_after_map_fall(Vector2(1200,555))
		player.set_physics_process(false)
		boss._recover(.55)
		var before:=boss.combat_stats.health
		for i in 12:
			var left:=boss.opening
			var recovery:=boss._recovery_age
			boss.receive_attack_hit(finisher,player.global_position)
			check(is_equal_approx(boss.opening,left) and is_equal_approx(boss._recovery_age,recovery),"Phase %d normal finisher cannot renew recovery"%phase)
			boss.receive_skill_hit(SkillHitContext.new(&"sword_wave_ground",1),player.global_position)
			check(is_equal_approx(boss.opening,left) and is_equal_approx(boss._recovery_age,recovery),"Phase %d skill cannot renew recovery"%phase)
			boss._update_opening(.05)
		check(boss.opening==0 and not boss.poise_broken and boss.short_stun_remaining==0,"Phase %d leaves recovery under sustained pressure"%phase)
		check(boss.combat_stats.health==before-12*(finisher.health_damage+1),"Normal finisher damage is unchanged")
		if phase!=4:
			boss.start_move(0,1800)
			boss.age=.25
			boss._execute_move()
			boss.receive_attack_hit(finisher,player.global_position)
			boss.receive_skill_hit(SkillHitContext.new(&"sword_wave_ground",1),player.global_position)
			check(boss.move==&"rush" and boss.opening==0 and boss.age==.25,"Hits preserve committed attack and windup clock")
	# The actual attack-3 effect/collision route, not only direct settlement.
	room.encounter._spawn_phase(1,1420)
	var boss:=room.deer
	boss.set_physics_process(false)
	boss.manual_control=true
	boss.invulnerable=false
	boss.start_move(2,1200)
	boss.age=.2
	boss._execute_move()
	player.reset_after_map_fall(Vector2(1300,555))
	player.set_physics_process(false)
	player.facing_direction=1
	player.attack_state=LanPlayer.AttackState.ATTACK_3X
	player._timeline_attack_3_effect_frame(7)
	var hp:=boss.combat_stats.health
	await wait_frames(8)
	check(boss.combat_stats.health==hp-finisher.health_damage,"Real normal finisher lands once through its painted hitbox")
	check(boss.move==&"sweep" and boss.age==.2 and boss.opening==0,"Real finisher does not cancel the BOSS attack")
	for effect in player.active_attack_effects.duplicate():
		if is_instance_valid(effect): effect.free()
	player.attack_state=LanPlayer.AttackState.NONE
	# Reproduce rising platform over an airborne foot, dash/recoil uphill, and
	# recovery from the reported embedded position in the production forest room.
	room.encounter._spawn_phase(2,1420)
	var deer:=room.deer as DeerRootDuelBoss
	deer.set_physics_process(false)
	deer.manual_control=true
	deer._ensure_contest_platform()
	player.reset_after_map_fall(Vector2(1280,540))
	player.set_physics_process(false)
	player.air_state=LanPlayer.AirState.FALLING
	deer.terrain.advance(2.5)
	check(is_equal_approx(player.position.y,415),"Rising solid platform catches airborne feet instead of enclosing them")
	player.position=Vector2(1280,555)
	deer.terrain.advance(.016)
	check(is_equal_approx(player.position.y,415),"Mature platform recovers the reported under-summit position")
	player.position=Vector2(1280,300)
	player.air_state=LanPlayer.AirState.RISING
	player.velocity.y=-400
	deer.terrain.advance(.016)
	check(player.position.y==300 and player.velocity.y==-400,"Valid jump above the summit is untouched")
	var edges:Vector2=deer.contest_wave.summit_edges()
	for side in [-1,1]:
		player.reset_after_map_fall(Vector2(edges.x-160 if side>0 else edges.y+160,555))
		player.set_physics_process(false)
		for f in 30:
			player.velocity=Vector2(side*1200,0)
			player.move_on_action_clock()
			check(player.position.y<=deer.ground_y_at(player.position.x)+.1,"Fast uphill motion cannot tunnel into the solid mound")
		check(player.position.y<=416,"Fast traversal reaches summit from either side")
	# Actual input drives a dash onto the slope; no test-side teleport during travel.
	for side in [-1,1]:
		player.reset_after_map_fall(Vector2(edges.x-125 if side>0 else edges.y+125,555))
		player.instant_dash_cooldown_remaining=0
		player.facing_direction=side
		deer.terrain.constrain_player(player)
		player.set_physics_process(true)
		await wait_frames(2)
		Input.action_press(&"ui_right" if side>0 else &"ui_left")
		var event:=InputEventKey.new()
		event.physical_keycode=KEY_U
		event.keycode=KEY_U
		event.pressed=true
		Input.parse_input_event(event)
		var penetrated:=false
		var dashed:=false
		for f in 45:
			await physics_frame
			dashed=dashed or player.attack_state==LanPlayer.AttackState.INSTANT_DASH
			penetrated=penetrated or player.position.y>deer.ground_y_at(player.position.x)+.5
		event.pressed=false
		Input.parse_input_event(event)
		Input.action_release(&"ui_right")
		Input.action_release(&"ui_left")
		check(dashed and not penetrated,"Real U dash crosses uphill without falling inside (dash=%s, penetration=%s, pos=%s)"%[dashed,penetrated,player.position])
		player.set_physics_process(false)
	player.reset_after_map_fall(Vector2(1180,415))
	player.set_physics_process(false)
	deer.position=Vector2(1430,415)
	deer._show_clip(&"idle_ING",0)
	await capture("root_supported")
	# Current production forest, both facings, actual attack time and contact geometry.
	for phase in [1,3]:
		room.encounter._spawn_phase(phase,1280)
		boss=room.deer
		boss.set_physics_process(false)
		boss.manual_control=true
		await wait_frames(2)
		player.reset_after_map_fall(Vector2(1070,555))
		player.set_physics_process(false)
		for side in [-1,1]:
			boss.cancel_duel(false)
			boss.position=Vector2(1400 if side<0 else 1190,555)
			boss.start_move(2,boss.position.x+side*220)
			for f in 48:
				boss._physics_process(1.0/60)
				if f==43: await capture("sweep_p%d_%d"%[phase,side])
			boss.cancel_duel(false)
			boss.position=Vector2(1450 if side<0 else 1030,555)
			if phase==3:
				boss.direction=side
				player.position.x=boss.position.x+side*450
				boss.preview_aim=player.position
				boss.plow.start()
			else: boss.start_move(0,boss.position.x+side*450)
			for f in 100:
				boss._physics_process(1.0/60)
				if f in [45,67,74]: await capture("blade_p%d_%d_%d"%[phase,side,f])
			check(boss.effects._main.is_empty(),"Studio blade releases with the completed contact")
	room.free()
	await wait_frames(3)
	expect_save_untouched()
	finish("DEER COMBAT FOLLOWUP")
