extends SceneTree
## Actual input/physics. No immunity, teleporting the player, or stopped hazards.
var failures:=0
var room: BossDevelopmentRoom
var held:=0
var report: Array=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
    if not ok:
        failures+=1
        if failures<15: push_error(message)
func walk(direction: int) -> void:
    if direction==held: return
    Input.action_release("ui_left")
    Input.action_release("ui_right")
    held=direction
    if direction: Input.action_press("ui_left" if direction<0 else "ui_right")

func cost(x: float,time: float,skill: SandstormThomas) -> float:
    var score:=0.0
    if x<48 or x>1232: return 100000.0
    var clearance:=150.0
    for wave in skill.waves:
        var age:=wave.age+time
        if age<wave.warning_time or age>=wave.warning_time+wave.active_time or wave.retiring>=0: continue
        var radius:=wave.base_radius+(age-wave.warning_time)*wave.speed
        var gap:=absf(absf(x-wave.birth_center.x)-radius)-wave.half_width-35
        if gap<0: score+=10000-gap*100
        clearance=minf(clearance,gap)
    if not skill.resting and not is_instance_valid(skill.follow):
        var boss_x:=skill.global_position.x+skill.move_velocity*minf(time,.3)
        var gap:=absf(x-boss_x)-145
        if gap<0: score+=2000-gap*30
    return score-minf(100,maxf(0,clearance))*.08

func choose_input(skill: SandstormThomas) -> int:
    # At the short side of the arena, step inside the opening warning ring
    # immediately. Chasing its outside edge would lead into the wall.
    if skill.waves.size()>=3 and skill.waves[0].age<skill.waves[0].warning_time:
        var opening:=skill.waves[0]
        var x:=room.player.position.x
        var room_needed:=opening.base_radius+opening.speed*opening.active_time+96
        if 1280-opening.birth_center.x<room_needed and x>opening.birth_center.x+opening.base_radius-60: return -1
        if opening.birth_center.x<room_needed and x<opening.birth_center.x-opening.base_radius+60: return 1
    var beam: Array=[{"x":room.player.position.x,"cost":0.0,"first":0,"last":held}]
    for step in 25:
        var choices: Array=[]
        var seen: Dictionary={}
        for state: Dictionary in beam:
            for direction in [0,-1,1]:
                var x: float=state.x+direction*LanPlayer.WALK_SPEED*.12
                var value: float=state.cost+cost(x,(step+1)*.12,skill)+absf(direction)*.12
                if direction!=state.last: value+=.2
                var key:="%d:%d"%[roundi(x/8),direction]
                if seen.has(key) and float(seen[key])<=value: continue
                seen[key]=value
                choices.append({"x":x,"cost":value,"first":direction if step==0 else state.first,"last":direction})
        choices.sort_custom(func(a: Dictionary,b: Dictionary): return a.cost<b.cost)
        beam=choices.slice(0,20)
    return int(beam[0].first)

func run() -> void:
    room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene=room
    await process_frame
    var cases: Array=[Vector2(380,0),Vector2(600,0),Vector2(100,0),Vector2(1180,0),Vector2(260,0),Vector2(900,-360),Vector2(100,-360)]
    if "--quick" in OS.get_cmdline_user_args(): cases=[Vector2(380,0)]
    if "--right" in OS.get_cmdline_user_args(): cases=[Vector2(1180,0)]
    if "--mirror" in OS.get_cmdline_user_args(): cases=[Vector2(900,-360),Vector2(100,-360)]
    for fixture: Vector2 in cases:
        var start_x:=fixture.x
        walk(0)
        if room.combat_simulation: room.set_combat_simulation(false)
        room.reset_room()
        room.select_combo(1)
        room.set_combat_simulation(true)
        room.player.position=Vector2(start_x,room.FLOOR_Y)
        var actor: SandstormFighter=room.adapter.boss
        actor.set_process(false)
        actor.position.x+=fixture.y
        actor.play_thomas() # Start after fixture placement so right-side cases face right.
        var skill: SandstormThomas=actor.thomas
        var events: Array=[]
        var contacts: Array=[]
        skill.wave_emitted.connect(func(wave: SandstormWave):
            events.append({"t":skill.elapsed,"x":wave.birth_center.x,"r":wave.base_radius,"speed":wave.speed,"velocity":skill.move_velocity})
            wave.hitbox.hit_resolved.connect(func(_target: Node,result: int): contacts.append({"t":skill.elapsed,"result":result})))
        var next_decision:=.40
        var start_hp:=room.player.combat_stats.health
        var minimum_hp:=start_hp
        var samples: Array=[]
        for tick in 1100:
            if not is_instance_valid(skill): break
            if skill.elapsed>=next_decision:
                next_decision=skill.elapsed+.12
                if is_instance_valid(skill.follow):
                    var f: SandstormThomasFollowup=skill.follow
                    walk(-1 if room.player.position.x<f.position.x else 1)
                else: walk(choose_input(skill))
            for wave in skill.waves:
                check(wave.global_position.distance_to(wave.birth_center)<.001,"Existing wave centre followed moving boss")
                check(is_equal_approx(wave.speed,float(skill.config.ring_speed)),"Existing wave speed changed")
                check(absf(wave.radius-(wave.base_radius+maxf(0,wave.age-wave.warning_time)*wave.speed))<.001,"Existing ring radius was retimed")
            check(not room.player.is_invulnerable(),"Walk test received immunity")
            check(skill.get_action_time_scale()==1,"Walk test slowed hazards")
            if tick%12==0: samples.append({"t":skill.elapsed,"boss_x":skill.position.x,"player_x":room.player.position.x,"input":held,"waves":skill.waves.size()})
            await physics_frame
            minimum_hp=mini(minimum_hp,room.player.combat_stats.health)
        walk(0)
        check(not is_instance_valid(skill) and actor.looping_idle,"Moving Thomas never finished")
        check(events.size()==6,"Expected initial triple plus three subsequent waves")
        if events.size()>=6:
            check(events[0].t==events[1].t and events[1].t==events[2].t,"Opening triple was staggered")
            check(events[0].x==events[1].x and events[1].x==events[2].x,"Opening triple used different origins")
            var first_delta: float=events[3].x-events[0].x
            var last_delta: float=events[5].x-events[4].x
            check(first_delta*last_delta<0,"Moving emitter never produced opposite spacing shifts")
        check(contacts.is_empty(),"Ordinary walking collided with a moving-emitter ring at x="+str(start_x))
        check(start_hp==minimum_hp,"Ordinary walking lost health at x="+str(start_x))
        print("MOVING THOMAS x=",start_x," HP=",minimum_hp," contacts=",contacts.size()," births=",JSON.stringify(events))
        report.append({"start_x":start_x,"boss_offset":fixture.y,"start_hp":start_hp,"minimum_hp":minimum_hp,"events":events,"contacts":contacts,"samples":samples})
    var out:="D:/HomingStar/homeing-star-test/artifacts/sandstorm-moving-thomas"
    DirAccess.make_dir_recursive_absolute(out)
    var report_name:="mirror_report.json" if "--mirror" in OS.get_cmdline_user_args() else "walk_report.json"
    FileAccess.open(out.path_join(report_name),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":report}))
    print("MOVING THOMAS: ",failures," failures")
    room.free()
    quit(1 if failures else 0)
