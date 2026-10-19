extends "../support/harness.gd"
## PaintedTimeline (restructure P6, 2026-10-19): the shared parse and frame lookup behind the
## deer, root, vine, wind-wall and twin-fish painted art. Checks the lookup rules every caller
## relied on and that the callers still answer as before at their boundaries.

func run() -> void:
	use_memory_progress()
	var durations := [100, 50, 200]
	check(PaintedTimeline.index_at(durations, 0.0) == 0 and PaintedTimeline.index_at(durations, 0.099) == 0, "Time inside the first frame finds frame 0")
	check(PaintedTimeline.index_at(durations, 0.1) == 1 and PaintedTimeline.index_at(durations, 0.149) == 1, "A frame starts exactly at its start time")
	check(PaintedTimeline.index_at(durations, 0.36) == -1, "Past the last frame is -1")
	check(PaintedTimeline.index_at(durations, 0.0999995, 0.000001) == 1, "An epsilon ends each frame that much early")
	check(PaintedTimeline.index_at(durations, 0.0, 0.0, 1) == 1 and PaintedTimeline.index_at(durations, 0.06, 0.0, 1, 2) == -1, "first/end limit the frames searched, timed from frame first")
	check(is_equal_approx(PaintedTimeline.seconds_before(durations, 2), 0.15) and is_equal_approx(PaintedTimeline.seconds_before(durations, 9), 0.35), "seconds_before sums whole frames, clipped to the list")
	check(PaintedTimeline.durations([{"duration_ms": 70}, {"duration_ms": 30}]) == [70, 30], "durations reads frame dictionaries")

	var lash := DeerVineLashArt.data()
	check(lash is Dictionary and DeerVineLashArt.data() == lash and PaintedTimeline.meta_json(DeerVineLashArt.TIMELINE, &"animation") == lash, "A timeline is parsed once and shared")
	check(DeerVineLashArt.frame_at(-0.1) == -1 and DeerVineLashArt.frame_at(DeerVineLashArt.total_time()) == -1 and DeerVineLashArt.frame_at(0.0) == 0, "Vine lash: hidden before and after, frame 0 at start")
	check(WindThornWallArt.frame_at(999.0) == WindThornWallArt.frame_count() - 1, "Thorn wall holds its last frame")
	var curtain_end := DeerVineCurtainArt.fade_start()
	check(DeerVineCurtainArt.frame_at(0, 999.0) == curtain_end - 1 and DeerVineCurtainArt.frame_at(0, -1.0) == -1, "Curtain growth holds before the fade and is hidden before it starts")
	check(DeerVineCurtainArt.frame_at(0, 0.0, true) == curtain_end, "Curtain dissolve starts at the fade frame")
	var library_clips: int = DeerActionLibrary.clips().size()
	var deer_only: Dictionary = PaintedTimeline.meta_json(DeerActionLibrary.MANIFEST, &"library_json")
	check(library_clips > (deer_only.clips as Dictionary).size(), "The action library merges human clips into its own copy, not into the shared parse")
	expect_save_untouched()
	finish("PAINTED TIMELINE")
