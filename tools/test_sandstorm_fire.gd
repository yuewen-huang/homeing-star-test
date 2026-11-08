extends SceneTree
const Fire=preload("res://scripts/bosses/sandstorm_fighter/sandstorm_fire_strike.gd")
var checks:=0
var failures:=0
func _initialize()->void: call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func run()->void:
	for scenario in [["pressure",688.0,false],["pressure",1080.0,false],["counter",688.0,false],["counter",1080.0,false],["pressure",688.0,true]]:
		var room:BossDevelopmentRoom=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
		root.add_child(room);current_scene=room
		await process_frame
		room.set_combat_simulation(true)
		var actor:SandstormFighter=room.adapter.boss;actor.set_process(false)
		room.player.position=Vector2(scenario[1],room.FLOOR_Y)
		actor.play_combat_combo(scenario[0])
		var seen:Dictionary={};var locked:Dictionary={};var directions:=true;var anchored:=true;var synchronized:=true;var intact:=true
		var charge_actions:Dictionary={};var quick_unlit:=true
		var sockets_ok:=true;var axes_ok:=true;var poses_ok:=true;var max_socket_error:=0.0
		var last_serial:=0;var distinct:Dictionary={};var captured:=false
		for tick in 420:
			await physics_frame
			if actor.looping_idle: break
			if not is_instance_valid(actor.melee): continue
			var melee:=actor.melee
			var nodes:=melee.find_children("*","Node2D",true,false)
			for node in nodes:
				if not node is Fire: continue
				seen[node.get_instance_id()]=true
				distinct[node.recipe.binding.action]=true
				if not node.released and node.renderer.visible:
					charge_actions[node.recipe.binding.action]=true
					quick_unlit=quick_unlit and node.recipe.binding.action in ["升龙拳","侧身斜上踢"]
				if node.released:
					var id:int=node.get_instance_id()
					if locked.has(id): anchored=anchored and (locked[id] as Transform2D).is_equal_approx(node.global_transform)
					else:
						locked[id]=node.global_transform
						var clip:Node2D=node.source_clip.get_ref()
						var cell:Vector2=clip.library.actions[clip.document.action].cell
						var sprite:Sprite2D=clip.body
						var expected:Vector2=sprite.to_global(node.socket_pixel-cell*.5)
						var nozzle:Vector2=node.renderer.to_global(Vector2(105,0))
						max_socket_error=maxf(max_socket_error,nozzle.distance_to(expected))
						sockets_ok=sockets_ok and nozzle.distance_to(expected)<.5
						var axis:Array=node.recipe.binding.force_axis
						var forward:Vector2=(sprite.to_global(node.socket_pixel-cell*.5+Vector2(axis[0],axis[1]))-expected).normalized()
						axes_ok=axes_ok and forward.dot(node.renderer.global_transform.x.normalized())>.999
						poses_ok=poses_ok and node.socket_frame>=int(node.recipe.binding.emission_frame) and node.socket_frame==clip._frame_at(clip.clock)
					var direction:Vector2=node.renderer.global_transform.x.normalized()
					directions=directions and direction.x*melee.facing>=-.0001
					synchronized=synchronized and node.age>=node.burst_at
					captured=true
			if melee.serial!=last_serial:
				last_serial=melee.serial
				# Each fire strike now owns exactly one spine collider; no particle hitboxes.
				for node in nodes:
					if node is Fire: intact=intact and node.find_children("*","Area2D",true,false).size()==1
			if scenario[2] and captured:
				actor.set_combat_enabled(false)
				await process_frame
				check(not is_instance_valid(actor.melee) and actor.find_children("*","MeshInstance2D",true,false).is_empty(),"Reset removes fire effect nodes")
				break
		check(seen.size()>0,"Fire appears: "+str(scenario))
		check(directions,"Fire direction follows actual facing: "+str(scenario))
		check(anchored,"Released fire stays in world space across pose handoffs")
		check(synchronized,"No burst ahead of source contact")
		check(intact,"One core collider per fire strike; no extra particle colliders")
		check(sockets_ok,"First burst nozzle matches actual rendered sprite pixel, max error="+str(max_socket_error))
		check(axes_ok,"Force axis matches sprite transform including left/right mirroring")
		check(poses_ok,"First burst uses extended limb frame, never stale previous pose")
		check(quick_unlit,"Quick links emit no pre-strike charging VFX")
		if not scenario[2]:
			check(charge_actions.size()==1 and charge_actions.has("升龙拳" if scenario[0]=="pressure" else "侧身斜上踢"),"Exactly one authored heavy charge per combo")
			check(actor.looping_idle and absf(actor._feet().y-room.FLOOR_Y)<.01,"Ground return after fire combo")
			check(distinct.size()==(6 if scenario[0]=="pressure" else 4),"All selected combo's authored fire variants are actually used")
		print("FIRE CASE ",scenario," variants=",distinct.size()," contacts=",last_serial)
		room.free();await process_frame
	print("SANDSTORM FIRE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
