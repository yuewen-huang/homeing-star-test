extends SceneTree
## Real development and production casts: random arrivals, early holds, simultaneous
## authored F11/F12/F13, damage shutdown, slow action clock, parry and reset cleanup.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room
var boss: DeerBoss
var vine: DeerVinePhase
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick(speed := 1.0) -> void:
	boss._physics_process(speed / 60.0)
	boss.vfx._process(speed / 60.0)
func until(predicate: Callable, limit := 1200) -> bool:
	for i in limit:
		if predicate.call(): return true
		tick()
	return bool(predicate.call())
func capture(label: String) -> void:
	if output.is_empty(): return
	# Manual simulation compresses seconds into one render frame. Remove the stale
	# transformation punch/flash so captures represent the current curtain state.
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.clear_body_reaction(boss.animated_sprite)
	feedback.screen_fx.clear()
	feedback._reset_punch()
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func frames(strike: DeerVineStrike) -> Array:
	var result := []
	for i in strike.columns.size(): result.append(strike.curtain_frame(i))
	return result

func verify_room(production: bool) -> void:
	var label := "production" if production else "development"
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn" if production else "res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.set_process(false); room.player.set_physics_process(false)
	boss = room.deer if production else room.adapter.deer
	boss.set_physics_process(false); boss.vfx.set_process(false)
	if production:
		room.player.reset_after_map_fall(Vector2(1250,555))
		boss.phase = 4; boss.reset_phase(); boss.manual_control = true
	else:
		room.select_combo(4); room.play_action(0)
		room.deflect_toggle.button_pressed = false
	vine = boss.vine_phase
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), label + " real transformation completes")
	room._process(0)
	(room.get_node("Camera2D") as Camera2D).force_update_scroll()
	seed(20261013 + int(production))
	check(vine.start_sequence(&"curtain"), label + " starts the real curtain sequence")
	var strike: DeerVineStrike = vine.strikes.back()
	var sorted_delays := strike.curtain_delays.duplicate(); sorted_delays.sort()
	check(strike.columns.size() == 33 and strike._curtain_sprites.size() == 33, label + " 33 painted columns cover 1280 world pixels")
	check(strike.curtain_delays != sorted_delays and strike.curtain_variants.min() != strike.curtain_variants.max(), label + " random spatial arrival order and art variant")
	check(frames(strike).all(func(frame: int) -> bool: return frame == -1) and strike.capsules().is_empty(), label + " warning has no visible vine or damage")
	check(strike._curtain_sprites.all(func(sprite: Sprite2D) -> bool: return sprite.scale == Vector2.ONE * 1.4), label + " all variants preserve the native 1.4 proportions")
	for i in strike.columns.size():
		check(strike._curtain_sprites[i].offset == -DeerVineCurtainArt.pivot(strike.curtain_variants[i]), label + " column %d preserves its authored pivot" % i)
	until(func() -> bool: return strike._age >= strike.warn - DeerVinePhase.RED_LEAD + 0.02)
	await capture(label + "_warning")
	until(func() -> bool: return strike._age >= strike.warn + 0.45)
	var mixed := frames(strike)
	check(mixed.min() == -1 and mixed.max() >= 4, label + " partial curtain mixes growing and not-yet-spawned columns")
	await capture(label + "_random_growth")
	var first: int = strike.curtain_delays.find(strike.curtain_delays.min())
	var last: int = strike.curtain_delays.find(strike.curtain_delays.max())
	until(func() -> bool: return strike._age >= strike.warn + 1.2)
	check(strike.curtain_frame(first) == 10 and strike.curtain_frame(last) < 10, label + " early vine waits on F10 while the latest still grows")
	await capture(label + "_early_wait")
	var before := strike._age
	for i in 12: tick(0.25)
	check(is_equal_approx(strike._age - before, 0.05), label + " all arrivals and holds share the quarter-speed action clock")
	until(func() -> bool: return strike._age >= strike.warn + strike.travel_time() + 0.1)
	check(frames(strike).all(func(frame: int) -> bool: return frame == 10) and strike.is_active(), label + " all vines hang together before shared dissolution")
	check(not strike.capsules().is_empty() and not is_nan(strike.touch(Rect2(strike.columns[16]-14,481,28,74)).x), label + " solid painted silhouette reaches the ground target")
	await capture(label + "_all_hanging")
	# Production AI cannot cancel the curtain by selecting another move while it hangs.
	if production:
		boss.manual_control = false
		tick()
		check(not strike.finished and vine.sequence_id == &"", label + " AI waits for the full painted curtain")
		boss.manual_control = true
	for frame in range(11,14):
		until(func() -> bool: return strike.curtain_frame(0) == frame)
		check(frames(strike).all(func(current: int) -> bool: return current == frame), label + " every column dissolves on F%d together" % frame)
		check(not strike.is_active() and strike.capsules().is_empty() and strike.hitbox.attack == null, label + " no damage during F%d dissolution" % frame)
		await capture(label + "_dissolve_%02d" % frame)
	check(until(func() -> bool: return strike.finished), label + " curtain finishes only after all three final frames")
	check(not strike.visible and strike.hitbox.attack == null, label + " full recovery clears visuals and damage")
	await capture(label + "_recovery")
	# Real red-counter callback: all already appearing vines break on the same final frames.
	var broken := vine.spawn_strike(&"curtain", room.player.position.x, boss.position.x, 0.0)
	broken.step(1.15)
	var shield := vine.shield
	broken.on_attack_parried(broken.hitbox.attack, Vector2(room.player.position.x,520))
	broken.step(0.01)
	check(broken.snapped and vine.shield == shield-2 and not broken.is_active() and broken.capsules().is_empty(), label + " red counter cracks two arcs and immediately removes damage")
	check(frames(broken).all(func(frame: int) -> bool: return frame == 11), label + " counter synchronizes the first painted breaking frame")
	broken.step(0.1)
	check(frames(broken).all(func(frame: int) -> bool: return frame == 12), label + " counter plays the second painted breaking frame")
	broken.step(0.1)
	check(frames(broken).all(func(frame: int) -> bool: return frame == 13), label + " counter plays the last painted breaking frame")
	broken.step(0.1)
	check(broken.finished, label + " counter cleanup completes")
	# Reset/cancel must also remove pending randomized arrivals and their children.
	var cancelled := vine.spawn_strike(&"curtain", room.player.position.x, boss.position.x, 1.0)
	vine.cancel()
	check(cancelled.finished and not cancelled.visible and vine.strikes.is_empty(), label + " reset cancels pending appearances in the specimen subtree")
	room.queue_free()
	await process_frame; await process_frame

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(true); assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	check(DeerVineCurtainArt.data().frame_count == 14 and DeerVineCurtainArt.fade_start() == 11 and is_equal_approx(DeerVineCurtainArt.fade_time(),0.3), "approved four clips have 14 native frames and a three-frame 300ms dissolution")
	await verify_room(false)
	await verify_room(true)
	print("RED_CURTAIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
