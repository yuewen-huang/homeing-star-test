extends "../../support/harness.gd"
var deer: DeerBoss
var room: Node2D
func tick(seconds: float) -> void:
	for i in ceili(seconds*120):
		deer._physics_process(1.0/120)
		deer.vfx._process(1.0/120)
func reset() -> void:
	deer.phase = 2
	deer.reset_phase(true,false)
	deer.position = Vector2(850,555)
	deer.manual_control = true
	deer.short_stun_remaining = 0
	room.player.reset_after_map_fall(Vector2(560,555))
	room.player.set_physics_process(false)
func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	reset()
	deer.start_combo(&"root_steps")
	tick(.6)
	check(deer.root_phase.nodules.is_empty(),"First stomp does not litter a nodule")
	tick(2)
	check(deer.root_phase.nodules.size()==1,"Second stomp plants exactly one nodule")
	for x in [300,450,700,1000]: deer.root_phase.add_nodule(Vector2(x,555))
	check(deer.root_phase.nodules.size()==2,"Nodule count stays capped at two")
	var nodule := deer.root_phase.nodules[0]
	nodule.break_nodule()
	check(nodule.broken,"Nodules remain destructible before detonation")
	reset()
	deer.root_phase.pattern.start(false)
	tick(.75)
	var first := deer.root_phase.volleys[0]
	var locked: float = first._spikes[1].x
	room.player.position.x += 200
	tick(.1)
	check(first._spikes[1].x == locked,"Root position stays locked after telegraph begins")
	check(deer.root_phase.use_decoy(),"Decoy can be placed during pursuit")
	var decoy_x := deer.root_phase.decoy_at.x
	room.player.position.x -= 350
	tick(1.1)
	var second: DeerRootVolley = deer.root_phase.volleys.back()
	check(second._spikes[1].x == decoy_x,"Subsequent roots target stationary decoy")
	check(not second.no_player_damage and deer.root_phase.active and not deer.poise_broken,"Decoy redirects rather than deleting damage or winning the mechanic")
	tick(8)
	check(not deer.root_phase.active and deer.state in [DeerBoss.State.RECOVER,DeerBoss.State.IDLE],"Pursuit finishes and returns control")
	reset()
	deer.combat_stats.apply_poise_damage(30)
	var poise := deer.combat_stats.poise
	deer.root_phase.pattern.start(true)
	var max_live := 0
	var max_roots := 0
	var red: CombatAttackData
	var overlapping := false
	for i in 1500:
		tick(1.0/120)
		max_live = maxi(max_live,deer.root_phase.volleys.size())
		for v in deer.root_phase.volleys: max_roots=maxi(max_roots,v._spikes.size())
		if deer.attack_hitbox.attack != null and String(deer.attack_hitbox.attack.attack_id).begins_with("deer_root_horn_"):
			red = deer.attack_hitbox.attack
			for v in deer.root_phase.volleys: overlapping = overlapping or not v.active_rects().is_empty()
			break
	check(red != null and red.danger_type == CombatAttackData.DangerType.COUNTERABLE_DANGER,"Ultimate reaches red horn finisher without an item")
	check(not overlapping,"No live root hitboxes overlap red finisher")
	check(deer.combat_stats.poise==poise,"Long pressure sequence preserves earned poise damage")
	check(max_live<=3 and max_roots<=6,"Ultimate root waves have bounded concurrency and size")
	if red != null: deer.on_attack_parried(red,room.player.position)
	check(not deer.root_phase.active and deer.state==DeerBoss.State.RECOVER,"Red counter cancels pursuit into punish recovery")
	reset()
	for cycle in 15:
		deer.root_phase.spawn_tracking()
		tick(2.5)
	check(deer.root_phase.volleys.is_empty() and deer.root_phase.volley_pool.size()<=4,"Repeated waves retire into bounded pool")
	var pooled: int = deer.root_phase.volley_pool.back().get_instance_id()
	var reused := deer.root_phase.spawn_tracking()
	check(reused.get_instance_id()==pooled and not reused.hit_target and not reused.cancelled,"Reused volley resets damage ledger and cancellation")
	deer.root_phase.cancel_attacks()
	check(deer.root_phase.volleys.is_empty(),"Cancellation clears all active roots")
	room.free(); current_scene=null
	expect_save_untouched()
	finish("DEER ROOT REBUILD")
