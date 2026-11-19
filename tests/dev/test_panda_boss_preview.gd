extends "../support/harness.gd"
## Keeps the segmented playback and specimen lifecycle covered while the art changes.

const AIR_WRITE := &"yin_air_write"

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	await wait_frames(2)
	var index := -1
	for i in room.boss_picker.item_count:
		if room.boss_picker.get_item_text(i).contains("熊猫"):
			index = i
			break
	check(index >= 0, "Panda is selectable in the development room")
	if index < 0:
		finish("PANDA PREVIEW")
		return
	room.boss_picker.item_selected.emit(index)
	await wait_frames(2)
	var adapter = room.adapter
	check(adapter != null and adapter.boss is PandaBoss and adapter.panel != null, "Selecting Panda creates its specimen and action panel")
	if adapter == null or not adapter.boss is PandaBoss or adapter.panel == null:
		finish("PANDA PREVIEW")
		return
	var boss := adapter.boss as PandaBoss
	boss.set_process(false)
	adapter.panel.set_process(false)
	check(not room.dummy.visible and not adapter.supports_combat_simulation(), "Art preview cannot enter combat")
	check_air_write_segments(boss, adapter.panel)

	room.reset_room()
	await wait_frames(2)
	check(not is_instance_valid(boss) and room.adapter.boss is PandaBoss and room.adapter.boss.action == &"yang_idle", "Reset frees the specimen and restarts from idle")
	var old_panel = room.adapter.panel
	room.select_boss((index + 1) % room.boss_picker.item_count)
	await wait_frames(2)
	check(not is_instance_valid(old_panel) and not room.adapter.boss is PandaBoss, "Switching bosses frees the Panda panel")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("PANDA PREVIEW")


func check_air_write_segments(boss: PandaBoss, panel: Node) -> void:
	var spec := PandaActions.spec(AIR_WRITE)
	var start := PandaActions.segment_range(spec, PandaActions.SEGMENT_START)
	var loop := PandaActions.segment_range(spec, PandaActions.SEGMENT_ING)
	var tail := PandaActions.segment_range(spec, PandaActions.SEGMENT_END)
	var frame_time := 1.0 / float(spec.fps)
	var start_time := (start.y - start.x + 1) * frame_time
	var loop_time := (loop.y - loop.x + 1) * frame_time
	var tail_time := (tail.y - tail.x + 1) * frame_time
	var finished: Array[StringName] = []
	boss.action_finished.connect(func(action: StringName): finished.append(action))
	boss.play_action(AIR_WRITE)
	check(boss.segment == PandaActions.SEGMENT_START, "Air write starts in START")
	boss.tick(start_time + 2.0 * loop_time + 0.5 * frame_time)
	check(boss.segment == PandaActions.SEGMENT_ING and boss.animated_sprite.frame == loop.x, "ING loops without exiting the action")
	check(not panel.handle_key(KEY_E), "Panda preview leaves E to Lan")
	panel.handle_key(KEY_N)
	check(boss.end_requested and boss.segment == PandaActions.SEGMENT_ING, "N queues the end without cutting ING")
	boss.tick(loop_time)
	check(boss.segment == PandaActions.SEGMENT_END and boss.animated_sprite.frame == tail.x, "Queued end starts on the first recovery frame")
	boss.tick(tail_time + frame_time)
	check(boss.action == spec.then and finished == [AIR_WRITE], "END finishes exactly once before returning to idle")
