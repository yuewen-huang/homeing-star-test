extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var room: BossDevelopmentRoom=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene=room
    await process_frame
    room.set_combat_simulation(true)
    var actor: SandstormFighter=room.adapter.boss
    actor.set_process(false)
    var moves: Array=["counter","counter"] if "--quick" in OS.get_cmdline_user_args() else ["counter","pressure","counter","pressure","counter","counter","pressure","counter","ambush","thomas","descent","counter"]
    for key: String in moves:
        match key:
            "ambush": actor.play_ambush()
            "thomas": actor.play_thomas()
            "descent": actor.play_descent()
            _: actor.play_combat_combo(key)
        for tick in 1800:
            await physics_frame
            if actor.looping_idle: break
        var feet: Vector2=actor._feet()
        print("GROUND RETURN ",key," y=",feet.y," expected=",room.FLOOR_Y)
        if not actor.looping_idle or absf(feet.y-room.FLOOR_Y)>.01:
            failures+=1
            push_error("Return floor drift after "+key)
    print("SANDSTORM GROUND RETURNS: ",failures," failures")
    room.free()
    quit(1 if failures else 0)
