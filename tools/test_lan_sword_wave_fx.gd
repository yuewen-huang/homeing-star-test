extends SceneTree
## Effects of Lan's sword wave (H, LanSwordWaveFX / LanSwordWaveProjectile, 2026-10-19): gather on
## frames 1–3, smears on the three cuts, three mini ground waves (the user's pixel art) that
## really hit a training dummy once each, mana per hit, facing both ways, cleanup, every smear baked,
## progress untouched. Optional user args: an output folder, then "frames" to save every
## frame of the move against the dummy.

class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room: Node2D
var player: LanPlayer
var dummy: Node2D
var checks := 0
var failures := 0
var hits: Array[int] = []
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func baked(piece: PixelSlash) -> bool:
	return is_instance_valid(piece) and not piece._clip.is_empty()

func snapshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

## Plays one whole sword wave toward `facing` with the dummy `gap` px ahead; returns the
## projectiles seen.
func play(facing: float, capture := "") -> Dictionary:
	hits.clear()
	player.global_position = Vector2(0, 555)
	dummy.global_position = Vector2(facing * 260.0, 555)
	player.combat_stats.mana = 0.0
	await process_frame
	player.start_sword_wave(facing)
	var fx := player.sword_wave_fx
	var seen := {"wave": [], "pieces": [], "cuts": [], "all_baked": true, "wave_y": [], "frames": {}}
	check(fx.pieces.size() == 1 and fx.pieces[0].wind_profile == &"lan_gather" and baked(fx.pieces[0]), "Facing %d: the gather starts on frame 1 from the baked atlas" % facing)
	var f := 0
	while f < 300 and (player.attack_state == LanPlayer.AttackState.SWORD_WAVE or not fx.projectiles.is_empty()):
		await process_frame
		for piece in fx.pieces:
			if not is_instance_valid(piece) or seen.pieces.has(piece): continue
			seen.pieces.append(piece)
			seen.all_baked = seen.all_baked and baked(piece)
			if String(piece.wind_profile).begins_with("lan_cut"): seen.cuts.append(piece.wind_profile)
		for projectile in fx.projectiles:
			if not is_instance_valid(projectile): continue
			seen.frames[projectile.visual.frame] = true
			if not (seen.wave as Array).has(projectile):
				(seen.wave as Array).append(projectile)
				(seen.wave_y as Array).append(projectile.global_position.y)
				var art := projectile.visual
				check(signf(projectile.velocity.x) == facing and art.texture == LanSwordWaveProjectile.TEXTURE and art.flip_h == (facing > 0.0),
					"Facing %d: the wave runs forward with the user's art, mirrored when running right" % facing)
		if not capture.is_empty(): await snapshot(capture.path_join("frame_%03d.png" % f))
		f += 1
	return seen

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	var capture := args.size() > 1 and args[1] == "frames"
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	var previous := root.get_node("SaveProgress")
	root.remove_child(previous)
	previous.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	room = Node2D.new()
	root.add_child(room)
	current_scene = room
	var camera := Camera2D.new()
	camera.position = Vector2(0, 450)
	room.add_child(camera)
	camera.make_current()
	player = load("res://scenes/sideview/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x = -2000.0
	player.world_max_x = 2000.0
	room.add_child(player)
	player.set_physics_process(false)
	dummy = load("res://scenes/sideview/training_dummy.tscn").instantiate()
	room.add_child(dummy)
	dummy.hit_received.connect(func(damage: int, _total: int) -> void: hits.append(damage))
	await process_frame

	for facing: float in [1.0, -1.0]:
		var folder := ""
		if capture and facing > 0.0:
			folder = output.path_join("sword_wave")
			DirAccess.make_dir_recursive_absolute(folder)
		var seen := await play(facing, folder)
		var cuts: Array = seen.cuts
		check(cuts == [&"lan_cut1", &"lan_cut2", &"lan_cut3"], "Facing %d: three cut smears in order %s" % [facing, str(cuts)])
		check(seen.all_baked, "Facing %d: every smear plays from the baked atlas" % facing)
		check((seen.wave as Array).size() == 3, "Facing %d: one ground wave per cut" % facing)
		check((seen.wave_y as Array).all(func(y) -> bool: return is_equal_approx(y, 555.0)), "Facing %d: the waves run along the ground" % facing)
		check((seen.frames as Dictionary).size() == LanSwordWaveProjectile.FRAME_COUNT, "Facing %d: the waves loop all four frames" % facing)
		var expected: Array[int] = [LanSwordWaveFX.WAVE_DAMAGE, LanSwordWaveFX.WAVE_DAMAGE, LanSwordWaveFX.HEAVY_WAVE_DAMAGE]
		check(hits == expected, "Facing %d: each projectile hits the dummy once (%s)" % [facing, str(hits)])
		check(is_equal_approx(player.combat_stats.mana, minf(3.0 * LanPlayer.MANA_GAIN_PER_HIT, player.combat_stats.max_mana)), "Facing %d: each hit gives Lan mana" % facing)
		check(player.sword_wave_fx.projectiles.is_empty() and room.find_children("LanGround*", "", false, false).is_empty(), "Facing %d: projectiles free themselves when spent" % facing)
		for k in 30: await process_frame
		check(player.sword_wave_fx.pieces.is_empty(), "Facing %d: the smears are gone after fading" % facing)

	# Every smear of the move is in the baked atlas.
	var missing: Array[String] = []
	var specs: Array = []
	for profile: StringName in [&"lan_gather", &"lan_cut1", &"lan_cut2", &"lan_cut3"]: specs.append(LanSwordWaveFX.spec(profile))
	for preset: Dictionary in specs:
		var probe := PixelSlash.new().configure(preset)
		room.add_child(probe)
		if probe._clip.is_empty(): missing.append(String(preset.get("wind_profile", preset.shape)))
		probe.free()
	check(missing.is_empty(), "Every sword wave effect is baked (missing %s)" % str(missing))

	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists, "Save existence unchanged")
	if exists: check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "In-memory fixture leaves progression byte-identical")
	current_scene = null
	room.free()
	print("LAN SWORD WAVE FX: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
