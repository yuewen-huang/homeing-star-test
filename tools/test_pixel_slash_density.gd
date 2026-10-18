extends SceneTree
## Confirms the approved two-world-pixel deer art is present and played from baked atlases.
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func run() -> void:
	var library := preload("res://assets/sideview/effects/combat_baked/library.tres")
	var manifest: Dictionary = JSON.parse_string(library.get_meta("manifest", "{}"))
	var deer_clips: Array[Dictionary] = []
	for clip: Dictionary in manifest.clips.values():
		if clip.spec.shape == "crescent" and clip.spec.palette == "deer": deer_clips.append(clip)
	check(PixelSlash.new().pixel_size == 3.0, "Shared effects retain their three-world-pixel default")
	check(deer_clips.size() >= 5, "The baked library contains the five production deer swing families")
	var quakes: Array = manifest.clips.values().filter(func(clip): return clip.spec.shape == "quake")
	check(quakes.size() == 5 and manifest.clips.size() >= 52, "The production library includes five crystal crab ground attack recipes")
	var semantically_named: bool = manifest.clips.values().all(func(clip: Dictionary) -> bool:
		var base := String(clip.get("asset_path", ""))
		if not base.contains("/") or base.is_empty(): return false
		for page: String in clip.get("pages", []):
			if not page.begins_with(base + "_") or not ResourceLoader.exists("res://assets/sideview/effects/combat_baked/" + page): return false
		return true)
	check(semantically_named, "Every production atlas page has an action-scoped path and resolves in Godot")
	check(deer_clips.all(func(clip: Dictionary) -> bool: return is_equal_approx(float(clip.pixel_size), 2.0)), "Every deer crescent is baked at the approved two-pixel density")
	if deer_clips.is_empty():
		print("PIXEL DENSITY: ", checks, " checks, ", failures, " failures")
		quit(1)
		return
	var preset: Dictionary = CombatVFXRecipe.decode(deer_clips[0].spec)
	var slash := PixelSlash.new().configure(preset)
	root.add_child(slash)
	await process_frame
	await process_frame
	check(slash._display != null and slash._display.texture is AtlasTexture, "Runtime deer crescents use a baked atlas frame")
	check(slash._display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Baked pixels use nearest-neighbour sampling")
	check(slash._display.scale.is_equal_approx(Vector2.ONE * 2.0), "Two-pixel art keeps the authored world-space scale")
	var bounds := slash.visual_bounds()
	check(bounds.size.x > 0.0 and bounds.size.y > 0.0, "The atlas frame reports visible world bounds")
	var first_frame := slash._current_frame
	slash.advance(0.05)
	check(slash.age >= 0.05 and slash._current_frame > first_frame, "Atlas frames follow the owner action clock")
	var held_age := slash.age
	slash.advance(0.0)
	check(is_equal_approx(slash.age, held_age), "A stopped action clock holds the current sprite frame")
	slash.queue_free()
	await process_frame
	print("PIXEL DENSITY: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
