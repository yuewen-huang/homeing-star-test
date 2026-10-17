extends SceneTree

class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func run() -> void:
	var real_save := root.get_node("SaveProgress")
	root.remove_child(real_save)
	real_save.free()
	var save := MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	var field := load("res://scenes/sideview/chapter_2_salt_field.tscn").instantiate() as SaltFieldPrototype
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	await process_frame
	await process_frame
	# Remove obstacle effects so this measures locomotion through the real map route.
	for pile in field.piles: pile.excavated = true
	var directions := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1,1).normalized(), Vector2(1,-1).normalized(),
		Vector2(-1,1).normalized(), Vector2(-1,-1).normalized()]
	var slowest := INF
	var fastest := 0.0
	for x in [480,3600,6720]:
		for y in [300,900,1500]:
			for running in [false,true]:
				for direction in directions:
					field.feet = Vector2(x,y)
					var before := SaltFieldProjection.project(field.feet)
					var scale := SaltFieldProjection.depth_scale(y)
					var speed := LanPlayer.RUN_SPEED if running else LanPlayer.WALK_SPEED
					field.step_exploration(1.0/60,direction,false,false,running)
					var motion := SaltFieldProjection.project(field.feet)-before
					var ratio := motion.length()/(speed*scale/60)
					slowest = minf(slowest,ratio)
					fastest = maxf(fastest,ratio)
					var label := "at %s direction %s running %s" % [Vector2(x,y),direction,running]
					check(absf(ratio-1.0)<0.005,"Consistent projected speed "+label+" ratio %.3f" % ratio)
					check(motion.normalized().dot(direction)>0.999,"Screen direction follows input "+label)
	print("Projected speed ratio range: %.3f to %.3f" % [slowest,fastest])
	field.feet = Vector2(480,900)
	# Hold and change diagonals for several seconds, including stopping afterward.
	for direction in [Vector2(1,1),Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1)]:
		for frame in 120:
			var before := SaltFieldProjection.project(field.feet)
			var expected := LanPlayer.WALK_SPEED*SaltFieldProjection.depth_scale(field.feet.y)/60
			field.step_exploration(1.0/60,direction,false,false)
			var motion := SaltFieldProjection.project(field.feet)-before
			check(absf(motion.length()-expected)<0.01,"Held diagonal retains its speed")
			check(motion.normalized().dot(direction.normalized())>0.999,"Held diagonal retains its screen direction")
	var stopped := field.feet
	field.step_exploration(1.0/60,Vector2.ZERO,false,false)
	check(field.feet==stopped,"Releasing movement stops immediately")
	field.free()
	current_scene = null
	await process_frame
	print("SALT MOVEMENT PROJECTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
