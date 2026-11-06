extends "../../support/harness.gd"
class HeldRoom extends Chapter1DeerBossRoom:
	var returned := false
	func _return_after_defeat() -> void: returned=true
func run() -> void:
	use_memory_progress()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	var room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	room.set_script(HeldRoom)
	var comic := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(comic)
	comic.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(3)
	room.player.set_physics_process(false)
	for phase in [2,3,4]:
		room.restart_mist_phase()
		room.encounter._spawn_phase(phase,1500)
		room.encounter.start()
		var actor: DeerDuelBoss=room.deer
		actor.set_physics_process(false)
		if phase==2:
			actor._ensure_contest_platform()
			actor.terrain.advance(2.4)
			check(not room.player.sloped_ground_surfaces.is_empty(),"Fixture creates actual root support")
		elif phase==3:
			actor.start_phrase(2)
		else:
			actor.transform_left=0
			actor.start_spell(1)
			actor._release_spell()
			check(not actor.spells.is_empty(),"Fixture creates detached wind spells")
		room.player.reset_after_map_fall(Vector2(1100,555))
		room.player.combat_stats.health=1
		var hit := CombatAttackData.new(StringName("fatal_%d"%phase),actor,30,0,0,0,CombatAttackData.DangerType.UNPARRYABLE_DANGER)
		room.player.receive_combat_hit(hit)
		check(room.player.combat_stats.health==0 and room._returning_after_defeat and not room.encounter.active,"Phase %d real lethal hit stops the encounter without practice refill"%phase)
		check(room.player.sloped_ground_surfaces.is_empty() and actor.attack_hitbox.attack==null,"Phase %d death clears terrain support and body contacts"%phase)
		if phase==3: check(actor.arena.hazards.is_empty(),"Vine hazards are cancelled on player death")
		if phase==4: check(actor.spells.is_empty(),"All detached wind spells are cancelled on actual player death")
		await wait_frames(2)
		check(room.returned and not actor.is_physics_processing(),"Defeat requests the normal exterior return and stays stopped")
	room.restart_mist_phase()
	room.deer.combat_stats.apply_health_damage(room.deer.combat_stats.health)
	room.player.combat_stats.apply_health_damage(room.player.combat_stats.health)
	for i in 180: room.encounter._physics_process(1.0/60)
	check(room.encounter.phase==1 and not room.encounter.transitioning,"Player death during handoff cannot spawn a later phase")
	current_scene=null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER DEATH CLEANUP")
