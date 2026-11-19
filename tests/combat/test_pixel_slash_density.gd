extends "../support/harness.gd"
## Baked pixel slashes retain the library's scale and follow action time.

func run() -> void:
	var library := preload("res://assets/generated/combat_vfx/library.tres")
	var manifest: Dictionary = JSON.parse_string(library.get_meta("manifest", "{}"))
	check(not manifest.clips.is_empty(), "Production atlas library contains clips")
	var crescent: Dictionary = {}
	for clip: Dictionary in manifest.clips.values():
		var base := String(clip.get("asset_path", ""))
		var pages: Array = clip.get("pages", [])
		check(base.contains("/") and not pages.is_empty() and pages.all(func(page: String) -> bool:
			return page.begins_with(base + "_") and ResourceLoader.exists("res://assets/generated/combat_vfx/" + page)
		), "Baked pages resolve under their action path: " + base)
		if crescent.is_empty() and clip.spec.shape == "crescent" and clip.spec.palette == "deer":
			crescent = clip
	check(not crescent.is_empty(), "A production deer crescent is available")
	if not crescent.is_empty():
		var slash := PixelSlash.new().configure(CombatVFXRecipe.decode(crescent.spec))
		root.add_child(slash)
		await wait_frames(2)
		var display := slash._display
		check(display != null and display.texture is AtlasTexture, "Runtime uses the baked atlas")
		if display != null:
			check(display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Baked pixels use nearest filtering")
			check(display.scale.is_equal_approx(Vector2.ONE * float(crescent.pixel_size)), "World scale follows the baked clip")
		slash.advance(0.05)
		var age := slash.age
		var frame := slash._current_frame
		check(age > 0.0, "Atlas playback follows the action clock")
		slash.advance(0.0)
		check(is_equal_approx(slash.age, age) and slash._current_frame == frame, "A paused clock keeps the current frame")
		slash.queue_free()
		await process_frame
	finish("BAKED PIXEL SLASH")
