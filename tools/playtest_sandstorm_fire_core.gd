extends SceneTree
## Open-loop player inputs. No hidden-state steering, immunity, player teleport,
## altered movement stats or skipped boss poses after the starting fixture.
const Fire=preload("res://scripts/bosses/sandstorm_fighter/sandstorm_fire_strike.gd")
var report:Array=[]
var tick_now:=0
var room:BossDevelopmentRoom
var out:="D:/HomingStar/homeing-star-test/artifacts/sandstorm-fire-core"
class CoreOverlay extends Node2D:
	var actor:Node2D
	func _process(_dt:float)->void: queue_redraw()
	func _draw()->void:
		if not is_instance_valid(actor): return
		for area in actor.find_children("*","Area2D",true,false):
			if not area is CombatHitbox2D or not area.monitoring: continue
			for collision in area.get_children():
				if not collision is CollisionShape2D or not collision.shape is ConvexPolygonShape2D: continue
				var points:=PackedVector2Array()
				for p in collision.shape.points: points.append(to_local(collision.to_global(p)))
				if points.size()<3: continue
				draw_colored_polygon(points,Color(0.1,1,.3,.18))
				points.append(points[0]);draw_polyline(points,Color(.1,1,.3,.9),1.5)
func _initialize()->void: call_deferred("run")
func dodge_key(down:bool)->void:
	var e:=InputEventKey.new();e.physical_keycode=KEY_L;e.pressed=down;Input.parse_input_event(e)
func release_inputs()->void:
	dodge_key(false)
	for a in ["ui_left","ui_right","ui_accept","parry"]: Input.action_release(a)
func run()->void:
	var only:=""
	Engine.max_fps=60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): only=arg.trim_prefix("--case=")
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(1280,720);root.position=Vector2i(-1500,0);root.unfocusable=true
	var cases:Array=[
		["pressure_stand","pressure",688.0,"stand"],
		["pressure_walk","pressure",688.0,"walk"],
		["pressure_jump","pressure",688.0,"jump"],
		["pressure_parry","pressure",688.0,"parry"],
		["pressure_dodge","pressure",688.0,"dodge"],
		["counter_stand","counter",1080.0,"stand"],
		["counter_walk","counter",1080.0,"walk"],
		["counter_jump","counter",1080.0,"jump"]]
	for fixture in cases:
		if not only.is_empty() and fixture[0]!=only: continue
		release_inputs()
		room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
		root.add_child(room);current_scene=room;await process_frame
		room.set_combat_simulation(true)
		var actor:SandstormFighter=room.adapter.boss;actor.set_process(false)
		if "--overlay" in OS.get_cmdline_user_args():
			var overlay:=CoreOverlay.new();overlay.actor=actor;overlay.z_index=100;room.add_child(overlay)
		room.player.position=Vector2(fixture[2],room.FLOOR_Y)
		actor.play_combat_combo(fixture[1])
		var hits:Array=[];var samples:Array=[];var registered:Dictionary={}
		root.get_node("BattleAssist").set_difficulty(1)
		var min_hp:=100;var immunity_frames:=0;var initial:=room.player.position
		var melee:SandstormMelee=actor.melee
		melee.attack_hitbox.hit_resolved.connect(func(_target:Node,result:int): hits.append({"kind":"body","result":result,"t":melee.elapsed,"tick":tick_now,"dodge_age":(room.player.dodge_elapsed() if room.player.ground_action_state==LanPlayer.GroundActionState.BACK_DODGE else -1.0),"ground_state":room.player.ground_action_state}))
		for tick in 380:
			tick_now=tick
			# React to the start of the visible combo, not its private contact clocks.
			if tick==18 and fixture[3] in ["walk","jump"]: Input.action_press("ui_left" if fixture[2]<820 else "ui_right")
			if fixture[3]=="jump":
				if tick==30: Input.action_press("ui_accept")
				if tick==34: Input.action_release("ui_accept")
			if fixture[3]=="parry":
				if tick==40: Input.action_press("parry")
				if tick==41: Input.action_release("parry")
			if fixture[3]=="dodge":
				if tick==36: dodge_key(true)
				if tick==37: dodge_key(false)
			if is_instance_valid(melee):
				for n in melee.find_children("*","Node2D",true,false):
					if not n is Fire: continue
					for area in n.renderer.get_children():
						if not area is CombatHitbox2D or registered.has(area.get_instance_id()): continue
						registered[area.get_instance_id()]=true
						var action:String=n.recipe.binding.action
						area.hit_resolved.connect(func(_target:Node,result:int): hits.append({"kind":action,"result":result,"t":melee.elapsed,"tick":tick_now,"dodge_age":(room.player.dodge_elapsed() if room.player.ground_action_state==LanPlayer.GroundActionState.BACK_DODGE else -1.0),"ground_state":room.player.ground_action_state}))
			await process_frame
			min_hp=mini(min_hp,room.player.combat_stats.health)
			if room.player.is_invulnerable(): immunity_frames+=1
			if tick%6==0: samples.append({"tick":tick,"x":room.player.position.x,"y":room.player.position.y,"hp":room.player.combat_stats.health})
			if DisplayServer.get_name()!="headless" and tick%2==0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join("%s_%04d.png"%[fixture[0],tick]))
			if actor.looping_idle: break
		release_inputs()
		var row:Dictionary={"case":fixture[0],"minimum_hp":min_hp,"immunity_frames":immunity_frames,"distance":room.player.position.x-initial.x,"hits":hits,"samples":samples,"defense_credit":actor.defense_credit}
		report.append(row);print("FIRE PLAY ",fixture[0]," hp=",min_hp," immunity=",immunity_frames," hits=",hits)
		room.free();await process_frame
	FileAccess.open(out.path_join("playtest"+("_"+only if not only.is_empty() else "")+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit()
