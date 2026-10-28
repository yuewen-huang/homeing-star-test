extends SceneTree

const SHEET := 256
# Per-action cell size override: yin_air_write was re-exported on a 350x350 canvas.
const CELLS := {&"yang_to_yin": 350, &"yin_air_write": 350}
# Independent of PandaActions on purpose: id -> [frames, sheet width, sheet height, end mode, then]
const EXPECTED := {
	&"yang_idle": [16, 1024, 1024, "loop", &""],
	&"yin_idle": [16, 1024, 1024, "loop", &""],
	&"yang_to_yin": [32, 1400, 2800, "idle", &"yin_idle"],
	&"yin_to_yang": [32, 1536, 1536, "idle", &"yang_idle"],
	&"yang_place_stone": [16, 1024, 1024, "idle", &"yang_idle"],
	&"yang_victory": [16, 1024, 1024, "hold", &""],
	&"yang_weak": [16, 1024, 1024, "loop", &""],
	&"yin_air_write": [32, 1400, 2800, "idle", &"yin_idle"],
	&"yin_weak": [16, 1024, 1024, "loop", &""],
}
const ORDER := [&"yang_idle", &"yin_idle", &"yang_to_yin", &"yin_to_yang", &"yang_place_stone",
	&"yang_victory", &"yang_weak", &"yin_air_write", &"yin_weak"]

var room
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func panda() -> PandaBoss:
	return room.adapter.boss as PandaBoss

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = code
	room.adapter.panel._unhandled_key_input(event)

func freeze() -> void:
	panda().set_process(false)
	room.adapter.panel.set_process(false)

func run() -> void:
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var save_before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	check_assets()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.player.set_physics_process(false)
	check(room.boss_picker.item_count == 10, "Ten bosses populate the selector")
	var index := -1
	for i in room.boss_picker.item_count:
		if room.boss_picker.get_item_text(i).contains("熊猫"): index = i
	check(index == 9, "Panda entry is the last catalog entry (index 9)")
	room.boss_picker.item_selected.emit(index)
	await process_frame
	await process_frame
	check(panda() != null and room.adapter.panel != null, "Room instantiates PandaBoss with its action panel")
	freeze()
	var boss := panda()
	check(is_equal_approx(boss.view_scale, 1.0) and boss.animated_sprite.scale.is_equal_approx(Vector2.ONE * PandaActions.DEFAULT_SCALE) and boss.animated_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Panda starts at default scale 1.0 with nearest filtering")
	check(not room.dummy.visible and not room.adapter.supports_combat_simulation(), "Panda preview has no dummy and no combat simulation")
	check(is_equal_approx(boss.global_position.y, room.FLOOR_Y), "Panda origin sits on the room floor line")
	check(boss.animated_sprite.offset == -PandaActions.FOOT_ANCHOR, "Foot anchor (128,249) maps to the sprite origin with zero default offset")
	check(room.adapter.action_names().size() == 9 and boss.action == &"yang_idle", "Nine actions listed; starts on yang_idle")
	check_air_write_canvas(boss)
	check_yang_to_yin_canvas(boss)
	check_air_write_segments(boss)
	check(boss.get("attack_hitbox") == null and boss.get("combat_stats") == null, "Panda carries no hitbox or combat stats")
	check(Array(PandaActions.SCALE_PRESETS) == [0.6, 0.75, 1.0, 1.25, 1.5] and PandaActions.DEFAULT_SCALE == 1.0, "Scale presets are 0.6/0.75/1.0/1.25/1.5 and the default is 1.0")
	check_scale_baselines()
	check(absf(boss.height_multiple() - 2.0) < 0.15 and boss.scale_text().contains("1.00") and room.adapter.telemetry().contains("1.00"), "Default scale makes the panda about twice Lan's height and the UI shows scale and multiple")
	check_foot_anchor_all_scales(boss)
	var panel = room.adapter.panel
	panel.select_scale(2)
	press(KEY_EQUAL)
	check(is_equal_approx(boss.view_scale, 1.25), "= steps the scale up to 1.25")
	press(KEY_PAGEUP)
	check(is_equal_approx(boss.view_scale, 1.5), "PageUp steps the scale up to 1.5")
	press(KEY_PAGEUP)
	check(is_equal_approx(boss.view_scale, 1.5), "Scale stops at the largest preset")
	press(KEY_MINUS)
	press(KEY_MINUS)
	check(is_equal_approx(boss.view_scale, 1.0), "- steps the scale down twice to 1.0")
	press(KEY_PAGEDOWN)
	check(is_equal_approx(boss.view_scale, 0.75), "PageDown steps the scale down to 0.75")
	press(KEY_KP_SUBTRACT)
	press(KEY_KP_SUBTRACT)
	check(is_equal_approx(boss.view_scale, 0.6), "Scale stops at the smallest preset")
	panel.scale_buttons[3].pressed.emit()
	check(is_equal_approx(boss.view_scale, 1.25) and panel.scale_index() == 3 and panel.scale_label.text.contains("1.25"), "Scale button 1.25 applies and the readout follows")
	panel.select_scale(2)
	check_height_reference(boss, panel)
	# Every action can be switched to through keys 1-9 and starts from frame 0.
	for i in ORDER.size():
		press(KEY_1 + i)
		check(boss.action == ORDER[i] and boss.animated_sprite.animation == ORDER[i] and boss.animated_sprite.frame == 0, "Key %d switches to %s at frame 0" % [i + 1, ORDER[i]])
		check(boss.status_text().contains(String(ORDER[i])) and boss.status_text().contains("F00"), "Status text shows name and frame for %s" % ORDER[i])
	# Playback rules per action.
	for id in ORDER:
		var data: Array = EXPECTED[id]
		var fps: float = PandaActions.spec(id).fps
		boss.play_action(id)
		boss.tick(1.5 / fps)
		check(boss.animated_sprite.frame == 1, "%s advances to frame 1 after 1.5 frame durations" % id)
		boss.tick((data[0] + 2.0) / fps)
		if PandaActions.is_segmented(PandaActions.spec(id)):
			check(boss.action == id and boss.segment == PandaActions.SEGMENT_ING and not boss.holding, "%s keeps looping its ING segment past its full length and only ends on request" % id)
			continue
		match data[3]:
			"loop":
				check(boss.action == id and not boss.holding and boss.animated_sprite.frame < data[0], "%s loops and keeps playing" % id)
			"idle":
				check(boss.action == data[4] and boss.animated_sprite.frame == 0, "%s plays once then returns to %s" % [id, data[4]])
			"hold":
				check(boss.action == id and boss.holding and boss.animated_sprite.frame == data[0] - 1, "%s plays once and holds the last frame" % id)
	# Forced loop preview.
	press(KEY_BACKSLASH)
	check(boss.force_loop and room.adapter.panel.loop_toggle.button_pressed, "Backslash toggles all-loop preview")
	for id in ORDER:
		boss.play_action(id)
		boss.tick((EXPECTED[id][0] + 3.0) / float(PandaActions.spec(id).fps))
		check(boss.action == id and not boss.holding, "%s keeps looping when all-loop preview is on" % id)
	press(KEY_BACKSLASH)
	check(not boss.force_loop, "Backslash toggles all-loop preview back off")
	# Bracket stepping wraps around.
	press(KEY_1)
	press(KEY_BRACKETLEFT)
	check(boss.action == &"yin_weak", "[ wraps from the first action to the last")
	press(KEY_BRACKETRIGHT)
	check(boss.action == &"yang_idle", "] wraps from the last action to the first")
	# Room buttons / keys use the adapter list and the same state.
	room.play_action(2)
	check(boss.action == &"yang_to_yin", "Room action button 3 plays yang_to_yin")
	room.adapter.panel.buttons[8].pressed.emit()
	check(boss.action == &"yin_weak", "Panel button 9 plays yin_weak")
	# Reset and boss switching free the specimen with its panel.
	var old_boss := boss
	room.reset_room()
	await process_frame
	await process_frame
	check(not is_instance_valid(old_boss) and panda().action == &"yang_idle", "Room reset respawns the panda on yang_idle")
	check(panda().view_scale == PandaActions.DEFAULT_SCALE and is_equal_approx(panda().animated_sprite.scale.x, 1.0), "Room reset respawns the panda at the default scale")
	var old_panel = room.adapter.panel
	room.boss_picker.item_selected.emit(1)
	await process_frame
	await process_frame
	check(not is_instance_valid(old_panel) and not (room.adapter.boss is PandaBoss), "Switching to another BOSS frees the panda and its panel")
	current_scene = null
	room.free()
	await process_frame
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == save_before), "User save remains byte-identical")
	print("PANDA BOSS PREVIEW: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func check_assets() -> void:
	check(PandaActions.ACTIONS.size() == EXPECTED.size(), "Action table lists nine actions")
	var frames := PandaActions.build_sprite_frames()
	var names: Array[String] = []
	for n in frames.get_animation_names(): names.append(String(n))
	names.sort()
	var expected_names: Array[String] = []
	for k in EXPECTED.keys(): expected_names.append(String(k))
	expected_names.sort()
	check(names == expected_names, "SpriteFrames animation names match the nine English ids")
	for id in EXPECTED:
		var data: Array = EXPECTED[id]
		var spec := PandaActions.spec(id)
		check(not spec.is_empty() and spec.file == "%s_%dx%d_%df.png" % [id, CELLS.get(id, SHEET), CELLS.get(id, SHEET), data[0]], "%s file name follows <action>_<W>x<H>_<N>f.png" % id)
		check(frames.get_frame_count(id) == data[0], "%s has %d frames" % [id, data[0]])
		check(frames.get_animation_loop(id) == (data[3] == "loop"), "%s loop flag matches its action nature" % id)
		var texture := load(PandaActions.texture_path(spec)) as Texture2D
		check(texture != null and texture.get_width() == data[1] and texture.get_height() == data[2], "%s sheet is %dx%d" % [id, data[1], data[2]])
		var image := texture.get_image()
		var cell_size: int = CELLS.get(id, SHEET)
		var cols := texture.get_width() / cell_size
		var rows := texture.get_height() / cell_size
		var all_ok := true
		var size_ok := true
		for i in data[0]:
			var frame := frames.get_frame_texture(id, i) as AtlasTexture
			size_ok = size_ok and frame.get_size() == Vector2(cell_size, cell_size) and frame.filter_clip
			var cell := image.get_region(Rect2i((i % cols) * cell_size, (i / cols) * cell_size, cell_size, cell_size))
			all_ok = all_ok and cell.get_used_rect().size != Vector2i.ZERO
		check(size_ok, "%s frames are %dx%d atlas cells with filter_clip" % [id, cell_size, cell_size])
		check(all_ok, "%s has artwork in every frame cell" % id)
		var tail_empty := true
		for i in range(data[0], cols * rows):
			var cell := image.get_region(Rect2i((i % cols) * cell_size, (i / cols) * cell_size, cell_size, cell_size))
			tail_empty = tail_empty and cell.get_used_rect().size == Vector2i.ZERO
		check(tail_empty, "%s unused trailing cells are empty (frame count is not over-read)" % id)
		var import_text := FileAccess.get_file_as_string(PandaActions.texture_path(spec) + ".import")
		check(import_text.contains("mipmaps/generate=false") and not import_text.contains("compress/mode=1"), "%s imports lossless without mipmaps" % id)

func check_scale_baselines() -> void:
	var lan := (load(PandaActions.LAN_IDLE_SHEET) as Texture2D).get_image().get_region(Rect2i(Vector2i.ZERO, PandaActions.LAN_IDLE_FRAME))
	check(lan.get_used_rect().size.y == 55 and is_equal_approx(PandaActions.LAN_REFERENCE_HEIGHT, 82.5), "Lan idle frame 0 is 55 opaque rows x 1.5 = 82.5 screen px")
	var yang := (load(PandaActions.texture_path(PandaActions.spec(&"yang_idle"))) as Texture2D).get_image().get_region(Rect2i(Vector2i.ZERO, Vector2i(SHEET, SHEET)))
	var rect := yang.get_used_rect()
	check(rect.size.y == int(PandaActions.PANDA_REFERENCE_HEIGHT) and rect.end.y == int(PandaActions.FOOT_ANCHOR.y) + 1, "yang_idle frame 0 opaque height %d texels ends on the foot row" % rect.size.y)

func check_foot_anchor_all_scales(boss: PandaBoss) -> void:
	var multiples := []
	for i in PandaActions.SCALE_PRESETS.size():
		var scale: float = PandaActions.SCALE_PRESETS[i]
		room.adapter.panel.select_scale(i)
		var ok := is_equal_approx(boss.animated_sprite.scale.x, scale) and boss.animated_sprite.scale.x == boss.animated_sprite.scale.y
		for id in ORDER:
			boss.play_action(id)
			var anchor := PandaActions.foot_anchor(PandaActions.spec(id))
			var foot: Vector2 = boss.animated_sprite.get_global_transform() * (boss.animated_sprite.offset + anchor)
			ok = ok and boss.animated_sprite.offset == -anchor and foot.is_equal_approx(boss.global_position) and is_equal_approx(foot.y, room.FLOOR_Y)
		check(ok, "Scale %s keeps the foot anchor on the floor line and the sprite offset unchanged for all nine actions" % scale)
		check(is_equal_approx(boss.height_multiple(), PandaActions.PANDA_REFERENCE_HEIGHT * scale / 82.5), "Scale %s is %.2fx Lan's height" % [scale, boss.height_multiple()])
		multiples.append(snappedf(boss.height_multiple(), 0.01))
	print("PRESET MULTIPLES: ", PandaActions.SCALE_PRESETS, " -> ", multiples)
	boss.play_action(&"yang_idle")

func check_height_reference(boss: PandaBoss, panel) -> void:
	var reference = panel.reference
	check(reference is PandaHeightReference and reference.visible and is_instance_valid(reference.sprite), "Static Lan height reference exists and is visible by default")
	var atlas := reference.sprite.texture as AtlasTexture
	check(atlas != null and atlas.atlas.resource_path == PandaActions.LAN_IDLE_SHEET and atlas.region == Rect2(0, 0, 46, 55), "Reference is Lan's real idle sheet, frame 0 (46x55)")
	var state := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).get_state()
	var matched := false
	for n in state.get_node_count():
		if state.get_node_name(n) != &"AnimatedSprite2D": continue
		var position := Vector2.ZERO
		var sprite_scale := Vector2.ONE
		for p in state.get_node_property_count(n):
			if state.get_node_property_name(n, p) == &"position": position = state.get_node_property_value(n, p)
			if state.get_node_property_name(n, p) == &"scale": sprite_scale = state.get_node_property_value(n, p)
		matched = reference.sprite.position == position and reference.sprite.scale == sprite_scale and sprite_scale.x == 1.5
	check(matched, "Reference sprite position and 1.5 scale match lan_player.tscn")
	check(reference.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and is_equal_approx(atlas.get_size().y * reference.sprite.scale.y, 82.5), "Reference uses nearest filtering and is 82.5 screen px tall")
	check(is_equal_approx(reference.global_position.y, room.FLOOR_Y) and reference.global_position.x < boss.global_position.x - 150.0, "Reference stands on the floor line beside the panda")
	var logic := false
	for node in reference.find_children("*", "", true, false): logic = logic or node is LanPlayer
	check(not logic and not reference.is_physics_processing(), "Reference carries no player logic")
	press(KEY_G)
	check(not reference.visible and not panel.reference_toggle.button_pressed, "G hides the reference")
	press(KEY_G)
	check(reference.visible and panel.reference_toggle.button_pressed, "G shows the reference again")

func check_air_write_canvas(boss: PandaBoss) -> void:
	var aw := PandaActions.spec(&"yin_air_write")
	check(PandaActions.frame_size(aw) == Vector2i(350, 350) and PandaActions.foot_anchor(aw) == Vector2(175, 296), "yin_air_write uses a 350x350 cell with foot anchor (175, 296)")
	var others := true
	for id in ORDER:
		if id != &"yin_air_write" and id != &"yang_to_yin":
			var spec := PandaActions.spec(id)
			others = others and PandaActions.frame_size(spec) == Vector2i(256, 256) and PandaActions.foot_anchor(spec) == Vector2(128, 249)
	check(others, "The other seven actions keep the 256x256 cell and foot anchor (128, 249)")
	var aw_image := (load(PandaActions.texture_path(aw)) as Texture2D).get_image()
	var idle_image := (load(PandaActions.texture_path(PandaActions.spec(&"yin_idle"))) as Texture2D).get_image()
	var idle_rect := idle_image.get_region(Rect2i(0, 0, 256, 256)).get_used_rect()
	var aw_rect := aw_image.get_region(Rect2i(0, 0, 350, 350)).get_used_rect()
	var idle_rel := Rect2i(idle_rect.position - Vector2i(PandaActions.FOOT_ANCHOR), idle_rect.size)
	var aw_rel := Rect2i(aw_rect.position - Vector2i(PandaActions.foot_anchor(aw)), aw_rect.size)
	check(idle_rel == aw_rel, "yin_air_write frame 0 body box matches yin_idle frame 0 relative to the foot anchor (%s)" % aw_rel)
	var margin := 999
	for i in 32:
		var rect := aw_image.get_region(Rect2i((i % 4) * 350, (i / 4) * 350, 350, 350)).get_used_rect()
		margin = mini(margin, mini(mini(rect.position.x, rect.position.y), mini(350 - rect.end.x, 350 - rect.end.y)))
	check(margin >= 20, "yin_air_write artwork keeps %d transparent texels from every cell edge in all 32 frames (no cropping)" % margin)
	boss.play_action(&"yin_idle")
	var idle_origin: Vector2 = boss.animated_sprite.get_global_transform() * (boss.animated_sprite.offset + PandaActions.FOOT_ANCHOR)
	boss.play_action(&"yin_air_write")
	var aw_origin: Vector2 = boss.animated_sprite.get_global_transform() * (boss.animated_sprite.offset + PandaActions.foot_anchor(aw))
	check(idle_origin.is_equal_approx(aw_origin), "Switching yin_idle to yin_air_write keeps the foot anchor at the same world point")
	check(is_equal_approx(boss.animated_sprite.scale.x, boss.view_scale), "Switching to the 350 canvas does not change the display scale")
	boss.play_action(&"yang_idle")

func check_air_write_segments(boss: PandaBoss) -> void:
	var aw := PandaActions.spec(&"yin_air_write")
	var fps := float(aw.fps)
	var S := PandaActions.SEGMENT_START
	var I := PandaActions.SEGMENT_ING
	var E := PandaActions.SEGMENT_END
	check(PandaActions.AIR_WRITE_ING_FIRST == 4 and PandaActions.AIR_WRITE_ING_LAST == 25, "ING boundaries are the AIR_WRITE_ING_FIRST/LAST constants 4 and 25 (0-based)")
	check(PandaActions.segment_range(aw, S) == Vector2i(0, 3) and PandaActions.segment_range(aw, I) == Vector2i(4, 25) and PandaActions.segment_range(aw, E) == Vector2i(26, 31), "Segments are START 0-3, ING 4-25, END 26-31")
	var counts := {S: 0, I: 0, E: 0}
	for f in 32: counts[PandaActions.segment_of(aw, f)] += 1
	check(counts[S] == 4 and counts[I] == 22 and counts[E] == 6, "The three segments partition all 32 frames (4 / 22 / 6)")
	check(not PandaActions.is_segmented(PandaActions.spec(&"yin_idle")) and not PandaActions.is_segmented(PandaActions.spec(&"yang_to_yin")), "Only yin_air_write is segmented")
	# START -> ING loops (twice and a bit).
	var changes: Array = []
	var finished: Array = []
	var on_change := func(segment: StringName) -> void: changes.append(segment)
	var on_finish := func(id: StringName) -> void: finished.append(id)
	boss.segment_changed.connect(on_change)
	boss.action_finished.connect(on_finish)
	press(KEY_8)
	check(boss.action == &"yin_air_write" and boss.segment == S and boss.animated_sprite.frame == 0 and not boss.end_requested, "Key 8 enters yin_air_write in START at frame 0")
	check(boss.status_text().contains("START") and boss.status_text().contains("F00"), "Status text shows the START segment and frame")
	boss.tick(0.5 / fps)
	var frames_ok := true
	var segments_ok := true
	for k in 70:
		var expected := k if k < 4 else 4 + (k - 4) % 22
		frames_ok = frames_ok and boss.animated_sprite.frame == expected
		segments_ok = segments_ok and boss.segment == (S if k < 4 else I)
		boss.tick(1.0 / fps)
	check(frames_ok, "START plays 0-3 once, then ING loops 4-25 over and over")
	check(segments_ok and changes == [S, I] and boss.action == &"yin_air_write" and not boss.holding, "Segment goes START then ING and stays in ING while looping")
	check(boss.status_text().contains("ING") and boss.status_text().contains("N"), "Status text shows ING and the N key hint")
	# N (not E) ends the loop: the current cycle finishes, then END plays once and idle returns.
	check(not room.adapter.panel.handle_key(KEY_E), "E is not a panda key (it belongs to Lan's controls)")
	while boss.animated_sprite.frame != 10: boss.tick(1.0 / fps)
	press(KEY_N)
	check(boss.end_requested and boss.segment == I and boss.animated_sprite.frame == 10 and boss.status_text().contains("END"), "N queues END without cutting the current ING frame")
	var tail: Array = []
	for k in 24:
		boss.tick(1.0 / fps)
		tail.append(boss.animated_sprite.frame)
		if boss.action != &"yin_air_write": break
	var expected_tail: Array = []
	for f in range(11, 26): expected_tail.append(f)
	for f in range(26, 32): expected_tail.append(f)
	check(tail.slice(0, 21) == expected_tail, "After N the cycle finishes at 25 and END plays 26-31 without a jump (%s)" % [tail.slice(0, 21)])
	check(changes == [S, I, E] and boss.action == &"yin_idle" and boss.animated_sprite.frame == 0 and boss.segment == &"" and finished == [&"yin_air_write"], "END plays once, finishes yin_air_write and returns to yin_idle")
	check(not boss.request_end() and not boss.end_requested, "request_end does nothing outside a segmented action")
	press(KEY_N)
	check(boss.action == &"yin_idle" and not boss.end_requested, "N is ignored on other actions")
	# N during START is queued: ING still plays one whole cycle before END.
	boss.play_action(&"yin_air_write")
	press(KEY_N)
	boss.tick(0.5 / fps)
	var seen: Array = []
	for k in 60:
		boss.tick(1.0 / fps)
		if boss.action != &"yin_air_write": break
		seen.append(boss.animated_sprite.frame)
	var queued_ok: bool = seen.size() >= 31 and seen[0] == 1
	for f in range(4, 26): queued_ok = queued_ok and seen.has(f)
	check(queued_ok and boss.action == &"yin_idle", "N pressed during START still plays one full ING cycle, then END, then yin_idle")
	# A huge time step lands inside ING and stays there.
	boss.play_action(&"yin_air_write")
	boss.tick(100.0)
	check(boss.action == &"yin_air_write" and boss.segment == I and boss.animated_sprite.frame >= 4 and boss.animated_sprite.frame <= 25, "A very long frame step stays inside the ING loop")
	# All-loop preview repeats the whole sequence: END wraps back to START instead of leaving.
	press(KEY_BACKSLASH)
	boss.play_action(&"yin_air_write")
	boss.tick(2.0)
	boss.request_end()
	var finished_before := finished.size()
	var wrapped := false
	for k in 60:
		boss.tick(1.0 / fps)
		wrapped = wrapped or boss.segment == S
	check(wrapped and boss.action == &"yin_air_write" and not boss.holding and finished.size() == finished_before, "All-loop preview repeats START -> ING -> END and never returns to idle")
	press(KEY_BACKSLASH)
	boss.segment_changed.disconnect(on_change)
	boss.action_finished.disconnect(on_finish)
	boss.play_action(&"yang_idle")

func check_yang_to_yin_canvas(boss: PandaBoss) -> void:
	var spec := PandaActions.spec(&"yang_to_yin")
	check(PandaActions.frame_size(spec) == Vector2i(350, 350) and PandaActions.foot_anchor(spec) == Vector2(175, 296) and spec.cols == 4 and spec.frames == 32, "yang_to_yin uses a 350x350 cell, 4 columns, 32 frames, foot anchor (175, 296)")
	var image := (load(PandaActions.texture_path(spec)) as Texture2D).get_image()
	var yang_rect := (load(PandaActions.texture_path(PandaActions.spec(&"yang_idle"))) as Texture2D).get_image().get_region(Rect2i(0, 0, 256, 256)).get_used_rect()
	var yin_rect := (load(PandaActions.texture_path(PandaActions.spec(&"yin_idle"))) as Texture2D).get_image().get_region(Rect2i(0, 0, 256, 256)).get_used_rect()
	var first := image.get_region(Rect2i(0, 0, 350, 350)).get_used_rect()
	var last := image.get_region(Rect2i((31 % 4) * 350, (31 / 4) * 350, 350, 350)).get_used_rect()
	var anchor := Vector2i(PandaActions.foot_anchor(spec))
	var yang_rel := Rect2i(yang_rect.position - Vector2i(PandaActions.FOOT_ANCHOR), yang_rect.size)
	var first_rel := Rect2i(first.position - anchor, first.size)
	check(absi(first_rel.position.x - yang_rel.position.x) <= 1 and absi(first_rel.end.x - yang_rel.end.x) <= 1 and absi(first_rel.position.y - yang_rel.position.y) <= 1 and first_rel.end.y == yang_rel.end.y, "yang_to_yin frame 0 body box matches yang_idle frame 0 relative to the foot anchor (%s vs %s)" % [first_rel, yang_rel])
	var yin_rel := Rect2i(yin_rect.position - Vector2i(PandaActions.FOOT_ANCHOR), yin_rect.size)
	var last_rel := Rect2i(last.position - anchor, last.size)
	check(last_rel == yin_rel, "yang_to_yin frame 31 body box equals yin_idle frame 0 relative to the foot anchor, so the hand-over has no jump (%s)" % last_rel)
	var margin := 999
	for i in 32:
		var rect := image.get_region(Rect2i((i % 4) * 350, (i / 4) * 350, 350, 350)).get_used_rect()
		margin = mini(margin, mini(mini(rect.position.x, rect.position.y), mini(350 - rect.end.x, 350 - rect.end.y)))
	check(margin >= 16, "yang_to_yin artwork keeps %d transparent texels from every cell edge in all 32 frames (no cropping, brush intact)" % margin)
	boss.play_action(&"yang_idle")
	var from_origin: Vector2 = boss.animated_sprite.get_global_transform() * (boss.animated_sprite.offset + PandaActions.FOOT_ANCHOR)
	boss.play_action(&"yang_to_yin")
	var y2y_origin: Vector2 = boss.animated_sprite.get_global_transform() * (boss.animated_sprite.offset + PandaActions.foot_anchor(spec))
	boss.tick(40.0 / float(spec.fps))
	var to_origin: Vector2 = boss.animated_sprite.get_global_transform() * (boss.animated_sprite.offset + PandaActions.FOOT_ANCHOR)
	check(boss.action == &"yin_idle" and from_origin.is_equal_approx(y2y_origin) and y2y_origin.is_equal_approx(to_origin) and is_equal_approx(boss.animated_sprite.scale.x, boss.view_scale), "yang_idle -> yang_to_yin -> yin_idle keeps the foot anchor at one world point at an unchanged scale")
	boss.play_action(&"yang_idle")
