extends SceneTree
## Physics probes test geometry/ledger boundaries only; playability is tested
## separately by playtest_sandstorm_fire_core.gd with the real Lan controller.
const Fire=preload("res://scripts/bosses/sandstorm_fighter/sandstorm_fire_strike.gd")
const Core=preload("res://assets/bosses/sandstorm_fighter/fx/fire/pressure_core.gd")
class Probe extends Node2D:
	var ids:Dictionary={}
	func _ready()->void:
		var hurt:=CombatHurtbox2D.new();hurt.collision_layer=4;hurt.collision_mask=0
		var shape:=CollisionShape2D.new();shape.shape=RectangleShape2D.new();shape.shape.size=Vector2(3,3)
		hurt.add_child(shape);add_child(hurt)
	func receive_combat_hit(attack:CombatAttackData)->int:
		ids[attack.attack_id]=int(ids.get(attack.attack_id,0))+1
		return CombatHitResult.Type.NORMAL_HIT
var failures:=0
var checks:=0
var verified:Dictionary={}
func _initialize()->void: call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func run()->void:
	for fixture in [["pressure",688.0],["counter",1080.0]]:
		var room:BossDevelopmentRoom=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
		root.add_child(room);current_scene=room;await process_frame
		room.set_combat_simulation(true)
		var actor:SandstormFighter=room.adapter.boss;actor.set_process(false)
		room.player.position=Vector2(fixture[1],room.FLOOR_Y)
		actor.play_combat_combo(fixture[0])
		var watched:Dictionary={};var records:Array=[]
		for tick in 380:
			await physics_frame
			if actor.looping_idle: break
			var melee:=actor.melee
			for n in melee.find_children("*","Node2D",true,false):
				if not n is Fire or not n.released or watched.has(n.get_instance_id()): continue
				watched[n.get_instance_id()]=true
				var spec:Dictionary=n.recipe.events[0]
				var action:String=n.recipe.binding.action
				var record:Dictionary={"action":action,"id":StringName("sandstorm_fire_%d"%n.get_instance_id()),"probes":[]}
				# Interior, distal bright core, visibly scattered flank, behind nozzle,
				# beyond the maximum luminous tip. Positions are fixed after setup.
				for p in [Vector2(105+250*float(spec.axis_length),0),Vector2(105+500*float(spec.axis_length),0),Vector2(105+250*float(spec.axis_length),100),Vector2(50,0),Vector2(105+700*float(spec.axis_length),0)]:
					var probe:=Probe.new();root.add_child(probe);probe.position=n.renderer.to_global(p);record.probes.append(probe)
				records.append(record)
				check(Core.damage_polygon(float(spec.windup)+float(spec.send)-.001,spec).is_empty(),action+" charge must be harmless")
				check(Core.damage_polygon(float(spec.windup)+float(spec.send)+.40,spec).is_empty(),action+" fading tail must be harmless")
		for record in records:
			for i in record.probes.size():
				var probe:Probe=record.probes[i]
				var count:=int(probe.ids.get(record.id,0))
				check(count==(1 if i<2 else 0),record.action+" probe "+str(i)+" hits="+str(count))
				probe.queue_free()
			verified[record.action]=true
		room.free();await process_frame
	check(verified.size()==8,"All eight action cores verified")
	print("FIRE CORE PHYSICS: %d checks, %d failures, %d actions"%[checks,failures,verified.size()])
	quit(1 if failures else 0)
