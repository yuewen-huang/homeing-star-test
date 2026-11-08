extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var room:=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene=room
	await process_frame
	for index in [0,1,3,8,10,11,12,13]:
		room.select_boss(index)
		var boss: DamageReceiver2D=room.adapter.boss
		var spacing: Node=boss.get_node("BodySpacing")
		boss.set_physics_process(false)
		boss.set_process(false)
		if boss is SandstormFighter:
			boss.combat_enabled=true
			boss.play_source("待机",true)
		else: boss.set("manual_control",false)
		if boss is MasterBoss:
			boss.combat_target=room.player
			boss.state=MasterBoss.State.RECOVER
		if boss is DeerDuelBoss:
			boss.opening=1
			boss.invulnerable=false
		room.player.input_frozen=false
		room.player.set_physics_process(true)
		var edge:=room.player.get_current_min_x()
		boss.global_position.x+=edge+2-spacing.center_x()
		room.player.global_position=Vector2(edge,room.FLOOR_Y)
		room.player.velocity=Vector2.ZERO
		for tick in 75: await physics_frame
		check(room.player.position.x>=edge-.01,"Pushed player past arena wall: "+str(index))
		check(spacing.center_x()-room.player.global_position.x>=spacing.gap_for(room.player)-.1,"Free boss did not yield at wall: "+str(index))
		# A raised body must not leave an invisible ground barrier.
		boss.global_position.y-=150
		check(not spacing.eligible(room.player),"Airborne boss blocked ground path: "+str(index))
		boss.global_position.y+=150
		boss.combat_stats.health=0
		check(not spacing.eligible(room.player),"Dead boss still pushes: "+str(index))
		print("SPACING EDGE ",index," failures=",failures)
	room.free()
	print("BOSS SPACING EDGES: ",failures," failures")
	quit(0 if failures==0 else 1)
