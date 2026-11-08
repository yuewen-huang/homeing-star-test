extends SceneTree
func _initialize()->void: call_deferred("run")
func stats(values:Array)->Dictionary:
	values.sort();var sum:=0.0
	for v in values: sum+=v
	return {"frames":values.size(),"mean_ms":sum/values.size(),"p95_ms":values[int(values.size()*.95)],"max_ms":values[-1]}
func run()->void:
	Engine.max_fps=60
	root.size=Vector2i(1280,720);root.position=Vector2i(-1500,-1500);root.unfocusable=true
	var room:BossDevelopmentRoom=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room);current_scene=room;await process_frame
	room.set_combat_simulation(true)
	var actor:SandstormFighter=room.adapter.boss;actor.set_process(false)
	room.player.position=Vector2(688,room.FLOOR_Y);actor.play_combat_combo("pressure")
	var frames:Array=[];var count:=0;var previous:=Time.get_ticks_usec()
	for i in 720:
		await process_frame
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		if i>=120: frames.append((now-previous)/1000.0)
		previous=now
		if actor.looping_idle:
			count+=1;actor.play_combat_combo("pressure" if count%2==0 else "counter")
	var result:=stats(frames);result["combos"]=count
	var output:="D:/HomingStar/homeing-star-test/artifacts/sandstorm-fire-performance.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("GAME FIRE PERFORMANCE: ",result)
	room.free();quit()
