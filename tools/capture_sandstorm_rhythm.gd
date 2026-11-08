extends SceneTree
## Capture the production room's real callbacks; never seek or advance a body manually.
var room: BossDevelopmentRoom
var out: String
var rows: Array=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var tag:="before"
	var only:=""
	var player_x:=688.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag=arg.trim_prefix("--tag=")
		if arg.begins_with("--only="): only=arg.trim_prefix("--only=")
		if arg.begins_with("--player-x="): player_x=float(arg.trim_prefix("--player-x="))
	out="D:/HomingStar/homeing-star-test/artifacts/sandstorm-rhythm/"+tag
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(1280,720)
	root.position=Vector2i(-1500,0)
	root.unfocusable=true
	room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	for kind in ["pressure","counter","descent","thomas","ambush"]:
		if not only.is_empty() and kind!=only: continue
		room.select_boss(13)
		room.select_combo(0 if kind=="descent" else (1 if kind=="thomas" else 2))
		room.set_combat_simulation(true)
		var actor: SandstormFighter=room.adapter.boss
		actor.set_process(false) # No repeat/AI replacement; child skills and real Lan continue.
		room.player.global_position=Vector2(player_x,room.FLOOR_Y)
		if kind in ["pressure","counter"]: actor.play_combat_combo(kind)
		var prior_contacts:=0
		for tick in 660:
			await process_frame
			if actor.looping_idle: break
			var sprite:=actor._body_sprite()
			if not is_instance_valid(sprite): continue
			var row: Dictionary={"case":kind,"tick":tick,"t":tick/60.0,"sample":actor.sample(),"body":[sprite.global_position.x,sprite.global_position.y],"visible":sprite.is_visible_in_tree() and sprite.modulate.a>.05,"player_hp":room.player.combat_stats.health}
			if is_instance_valid(actor.melee):
				row.root=[actor.melee.global_position.x,actor.melee.global_position.y]
				row.slot=actor.melee.playback.slot
				row.contacts=actor.melee.serial
				row.source_clock=actor.melee.playback.current.clock
			elif is_instance_valid(actor.descent):
				row.phase=actor.descent.phase
				row.phase_clock=actor.descent.clock
				row.root=[actor.descent.global_position.x,actor.descent.global_position.y]
			elif is_instance_valid(actor.ambush):
				row.phase=actor.ambush.phase
				row.phase_clock=actor.ambush.clock
				row.root=[actor.ambush.global_position.x,actor.ambush.global_position.y]
			else:
				row.root=[actor.thomas.global_position.x,actor.thomas.global_position.y]
				if is_instance_valid(actor.thomas.follow):
					var follow: SandstormThomasFollowup=actor.thomas.follow
					row.root=[follow.global_position.x,follow.global_position.y]
					row.phase=follow.phase
					row.phase_clock=follow.clock
					row.contacts=follow.serial
			if tick%2==0 and DisplayServer.get_name()!="headless":
				row.image=kind+"_%04d.png"%tick
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join(row.image))
			rows.append(row)
		print("RHYTHM CAPTURE ",tag," ",kind)
	FileAccess.open(out.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(rows))
	room.free()
	quit()
