extends "D:/HomingStar/homeing-star-test/tools/test_sandstorm_moving_waves.gd"

func run() -> void:
    root.size=Vector2i(1280,720)
    root.unfocusable=true
    root.position=Vector2i(-1500,-1500)
    room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene=room
    await process_frame
    room.select_combo(1)
    room.set_combat_simulation(true)
    room.player.position=Vector2(380,room.FLOOR_Y)
    for child in room.get_children():
        if child is CanvasLayer: child.hide()
    room.player.get_node("PlayerStatusHUD").hide()
    var actor: SandstormFighter=room.adapter.boss
    actor.set_process(false)
    var skill: SandstormThomas=actor.thomas
    var births: Array=[]
    var rows: Array=[]
    skill.wave_emitted.connect(func(wave: SandstormWave): births.append({"time":skill.elapsed,"x":wave.birth_center.x,"radius":wave.base_radius,"velocity":skill.move_velocity}))
    var next_decision:=.4
    var tail:=0
    for tick in 1000:
        if is_instance_valid(skill):
            if skill.elapsed>=next_decision:
                next_decision=skill.elapsed+.12
                walk(choose_input(skill))
            var rings: Array=[]
            for wave in skill.waves: rings.append({"center":wave.global_position.x,"radius":wave.radius,"age":wave.age})
            rows.append({"time":skill.elapsed,"boss_x":skill.position.x,"player_x":room.player.position.x,"input":held,"hp":room.player.combat_stats.health,"waves":rings})
        else:
            walk(0)
            tail+=1
            if tail>30: break
        await physics_frame
    var out:="D:/HomingStar/homeing-star-test/artifacts/sandstorm-moving-thomas"
    DirAccess.make_dir_recursive_absolute(out)
    FileAccess.open(out.path_join("recording.json"),FileAccess.WRITE).store_string(JSON.stringify({"births":births,"frames":rows}))
    print("MOVING RECORDING HP=",room.player.combat_stats.health," births=",JSON.stringify(births))
    room.free()
    quit()
