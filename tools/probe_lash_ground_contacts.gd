extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ribbon := DeerVineLashRibbon.new()
	root.add_child(ribbon)
	ribbon.setup(Vector2(610,555),1,1280)
	for frame in range(14,22):
		ribbon.sample(DeerVineLashArt.time_at_frame(frame))
		for strand in 2:
			var closest := -10000.0
			for i in range(1, ribbon.paths[strand].size()):
				if absf(ribbon.paths[strand][i].x - ribbon.origin.x) >= 56.0 * 2.8:
					closest = maxf(closest, ribbon.paths[strand][i].y + ribbon._radius(56.0 * (0.76 if strand == 0 else 1.0), i))
			print("GROUND_POSE ",frame," strand=",strand," nearest lower edge=",closest," tip=",ribbon.paths[strand][-1]," contacts=",ribbon.ground_contacts(strand))
	quit()
