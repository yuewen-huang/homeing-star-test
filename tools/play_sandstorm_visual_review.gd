extends SceneTree
## Visual-input review driver. No skill phase/contact-time information feeds controls.
## Simulation pauses only BETWEEN human/model-issued input batches; recordings omit waits.
var OUT="D:/HomingStar/homeing-star-test/artifacts/sandstorm-visual-review/"
var room: BossDevelopmentRoom
var tick:=0
var seq:=0
var movie_frame:=0
var commands:=[]
var observations:=[]
var damage_taken:=0
var previous_hp:=100
var refills:=0
func _initialize() -> void: call_deferred("run")
func key(code: int,down: bool) -> void:
	var e:=InputEventKey.new()
	e.physical_keycode=code
	e.pressed=down
	Input.parse_input_event(e)
func mouse(down: bool) -> void:
	var e:=InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=down
	Input.parse_input_event(e)
func release() -> void:
	for action in ["ui_left","ui_right","move_left","move_right","parry","jump"]: Input.action_release(action)
	key(KEY_L,false)
	mouse(false)
func snapshot() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"latest.png")
	var status:={"seq":seq,"seconds":tick/60.0,"player_hp":room.player.combat_stats.health,
		"boss_hp":room.adapter.boss.combat_stats.health,"damage_taken":damage_taken,"practice_refills":refills}
	FileAccess.open(OUT+"status.json",FileAccess.WRITE).store_string(JSON.stringify(status))
	print("VISUAL INPUT READY ",JSON.stringify(status))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): OUT=arg.trim_prefix("--out=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(OUT+"frames")
	root.size=Vector2i(1280,720)
	root.unfocusable=true
	root.position=Vector2i(-1500,-1500)
	room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	room.select_combo(3)
	root.get_node("BattleAssist").set_difficulty(1)
	room.set_combat_simulation(true)
	for child in room.get_children():
		if child is CanvasLayer: child.hide()
	room.player.get_node("PlayerStatusHUD").show()
	room.player.combat_stats.health_changed.connect(func(hp: int,_max: int):
		if hp<previous_hp: damage_taken+=previous_hp-hp
		elif hp>previous_hp: refills+=1
		previous_hp=hp)
	paused=true
	await snapshot()
	while true:
		await process_frame
		if not FileAccess.file_exists(OUT+"command.json"): continue
		var parser:=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(OUT+"command.json"))!=OK: continue
		var command=parser.data
		if not command is Dictionary or int(command.get("seq",0))<=seq: continue
		seq=int(command.seq)
		commands.append({"at":tick/60.0,"command":command})
		if command.get("stop",false): break
		release()
		paused=false
		var direction: float=float(command.get("walk",0))
		for i in range(clampi(int(command.get("frames",180)),1,3600)):
			if command.get("patrol",false):
				if room.player.position.x<100: direction=1
				elif room.player.position.x>1180: direction=-1
			Input.action_release("ui_left")
			Input.action_release("ui_right")
			if direction!=0: Input.action_press("ui_left" if direction<0 else "ui_right")
			if i==0:
				if command.get("jump",false): Input.action_press("jump")
				if command.get("dodge",false): key(KEY_L,true)
				if command.get("parry",false): Input.action_press("parry")
			if i==1:
				Input.action_release("jump")
				Input.action_release("parry")
				key(KEY_L,false)
			if command.get("attack",false): mouse(i%24==0)
			await physics_frame
			tick+=1
			if tick%4==0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT+"frames/frame_%05d.png"%movie_frame)
				movie_frame+=1
			# Post-run diagnostics only. Do not expose hidden state in observation/status.
			var actor=room.adapter.boss
			observations.append({"t":tick/60.0,"p":[room.player.position.x,room.player.position.y],
				"b":[actor._feet().x,actor._feet().y],"hp":room.player.combat_stats.health,"boss_hp":actor.combat_stats.health,
				"idle":actor.looping_idle,"action":actor.brain.last,"approaching":is_instance_valid(actor.approach),"title":actor.action_title})
			if actor.defeated_state: break
		release()
		paused=true
		await snapshot()
	release()
	FileAccess.open(OUT+"review.json",FileAccess.WRITE).store_string(JSON.stringify({"commands":commands,"observations":observations,
		"boss_history":room.adapter.boss.brain.history,"damage_taken":damage_taken,"practice_refills":refills,
		"method":"Visual decisions between paused batches; within each batch real 60Hz physics and normal inputs. No hidden timing used to choose controls."}))
	paused=false
	room.free()
	quit()
