extends SceneTree
const Ground := preload("res://scripts/bosses/master/studio_vfx/quake_effect.gd")
const Style := preload("res://scripts/bosses/master/studio_vfx/combo_style.gd")
const Score := preload("res://scripts/bosses/crystal_crab/crystal_crab_quake_rhythm.gd")
const Textures := preload("res://scripts/bosses/master/studio_vfx/quake/textures.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func snapshot(effect: Node2D, name_: String) -> Image:
	var image: Image
	if DisplayServer.get_name() == "headless": return image
	root.add_child(effect)
	effect.position = Vector2(640, 555)
	effect.advance(0.25)
	await process_frame
	await RenderingServer.frame_post_draw
	image = root.get_texture().get_image()
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if not output.is_empty(): image.save_png(output.path_join(name_ + ".png"))
	root.remove_child(effect)
	await process_frame
	return image
func run() -> void:
	for i in 6: await process_frame
	check(root.find_children("CombatShaderWarmup", "", true, false).is_empty(), "off-screen shader warmup cleans up its viewport")
	check(Engine.time_scale == 1 and (root.get_node("CombatFeedback") as CombatFeedbackService).shake_remaining <= 0, "warmup never requests hit stop or camera feedback")
	var baker := load(get_script().resource_path.get_base_dir().path_join("../../tools/art/bake_quake_textures.gd"))
	var originals: Array[Texture2D] = [baker.Source.soft(), baker.Source.puff(0), baker.Source.puff(1), baker.Source.puff(2), baker.Source.puff_atlas()]
	var baked: Array[Texture2D] = [Textures.soft(), Textures.puff(0), Textures.puff(1), Textures.puff(2), Textures.puff_atlas()]
	for index in originals.size():
		var original := originals[index].get_image()
		var picture := baked[index].get_image()
		picture.convert(original.get_format())
		check(original.get_data() == picture.get_data(), "baked texture preserves all original pixels: %d" % index)
	Style.load_data(Score.effect_style())
	var event := Score.effect_spec(320, 2)
	event.shake = 0
	Ground._geometry_cache.clear()
	var before := Time.get_ticks_usec()
	var first: Node2D = Ground.new().configure(event)
	var cold_ms := (Time.get_ticks_usec()-before)/1000.0
	before = Time.get_ticks_usec()
	var second: Node2D = Ground.new().configure(event)
	var repeat_ms := (Time.get_ticks_usec()-before)/1000.0
	check(first.bodies == second.bodies and first.cracks == second.cracks and first.puffs == second.puffs and first.debris == second.debris, "cached layout preserves every body, crack and particle")
	check(first.layers.keys() == second.layers.keys(), "cached layers preserve their names and traversal order")
	for key_: String in first.layers:
		var a: Node2D = first.layers[key_]
		var b: Node2D = second.layers[key_]
		check(a.material != b.material, "each instance owns its material: " + key_)
		check(a.get_index() == b.get_index() and a.z_index == b.z_index and a.visible == b.visible, "layer ordering and visibility preserved: " + key_)
		if a is MeshInstance2D:
			check(a.mesh == b.mesh, "immutable mesh is reused: " + key_)
	var first_image := await snapshot(first, "quake_cold")
	var second_image := await snapshot(second, "quake_cached")
	if first_image != null:
		check(first_image.get_data() == second_image.get_data(), "cold and cached effects render identical pixels")
	first.advance(0.3)
	check(is_equal_approx(float(first.layers.solids.material.get_shader_parameter("time")),0.55 if first_image != null else 0.3) and is_equal_approx(float(second.layers.solids.material.get_shader_parameter("time")),0.25 if second_image != null else 0.0), "advancing one effect cannot change another effect's clock")
	first.bodies[0].birth = 999.0
	check(float(second.bodies[0].birth) != 999, "mutable layout dictionaries are not shared")
	var relocated := event.duplicate(true)
	relocated.x = 1550
	relocated.y = 490
	relocated.shake = 12
	var third: Node2D = Ground.new().configure(relocated)
	check(third.position == Vector2(1550,490) and third.layers.solids.mesh == second.layers.solids.mesh and third.spec.shake == 12, "location and feedback stay instance-local while geometry is reused")
	var changed := event.duplicate(true)
	changed.seed = int(changed.seed) + 1
	var different: Node2D = Ground.new().configure(changed)
	check(different.layers.solids.mesh != second.layers.solids.mesh, "a different authored seed gets different geometry")
	first.free()
	second.free()
	third.free()
	different.free()
	for i in Ground.GEOMETRY_CACHE_LIMIT + 3:
		var tiny := Ground.new().configure({"unit":"earth","width":90+i,"body":false,"cracks":false,"dust":false,"debris":"none"})
		tiny.free()
	check(Ground._geometry_cache.size() <= Ground.GEOMETRY_CACHE_LIMIT, "geometry cache has a fixed memory bound")
	print("QUAKE CACHE setup cold_ms=",cold_ms," cached_ms=",repeat_ms)
	print("QUAKE CACHE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
