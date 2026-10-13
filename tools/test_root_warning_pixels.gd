extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var volley := RootSpikeVolley.new()
	var cases := 0
	var failures := 0
	# All warning radii used by the ten painted root clips, including the
	# continuously closing outer ellipse at each 60 Hz warning tick.
	for key in DeerRootArt.data().clips:
		var clip := DeerRootArt.clip(key)
		var frame: Dictionary = clip.frames.back()
		var width := maxi(7, roundi(float(frame.hit_rect[2]) * 0.65 * 1.4 / RootSpikeVolley.PIXEL))
		var rx := width * RootSpikeVolley.PIXEL * 0.4 + RootSpikeVolley.RING_PADDING
		for tick in 61:
			var scale := lerpf(2.2, 1.0, tick / 60.0)
			var x_radius := rx * scale
			var y_radius := RootSpikeVolley.RING_HEIGHT * scale
			var cx_max := ceili(x_radius / RootSpikeVolley.PIXEL)
			var cy_max := ceili(y_radius / RootSpikeVolley.PIXEL)
			for filled in [true, false]:
				cases += 1
				var matches := true
				for cy in range(-cy_max, cy_max + 1):
					var half := volley._ellipse_row_half_width(cy, x_radius, y_radius)
					var interior := mini(half - 1, mini(volley._ellipse_row_half_width(cy - 1, x_radius, y_radius), volley._ellipse_row_half_width(cy + 1, x_radius, y_radius)))
					for cx in range(-cx_max, cx_max + 1):
						var old_pixel := volley._in_ellipse(cx, cy, x_radius, y_radius)
						if old_pixel and not filled:
							old_pixel = not (volley._in_ellipse(cx - 1, cy, x_radius, y_radius) and volley._in_ellipse(cx + 1, cy, x_radius, y_radius) and volley._in_ellipse(cx, cy - 1, x_radius, y_radius) and volley._in_ellipse(cx, cy + 1, x_radius, y_radius))
						var new_pixel: bool = half >= 0 and absi(cx) <= half and (filled or interior < 0 or absi(cx) > interior)
						if old_pixel != new_pixel: matches = false
				if not matches:
					failures += 1
					print("FAIL ", key, " tick=", tick, " filled=", filled)
	volley.free()
	print("ROOT_WARNING_PIXELS: %d masks, %d mismatches" % [cases, failures])
	quit(1 if failures else 0)
