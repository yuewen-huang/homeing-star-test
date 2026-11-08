extends SceneTree
func _initialize() -> void:
    var f=load("res://scripts/levels/chapter_2_salt/chapter_2_salt_field.gd").new()
    f._build_piles()
    for p in f.piles:
        if p.ground_position.x>5600 and p.ground_position.y<1300:
            print(p.ground_position)
    for x in [5800,5900,6000,6100,6200]:
        for y in [800,850,900,950,1000,1050,1100]:
            var nearest=INF
            for p in f.piles: nearest=minf(nearest,p.ground_position.distance_to(Vector2(x,y)))
            if nearest>200: print("clear ",Vector2(x,y)," distance ",nearest)
    f.free()
    quit()
