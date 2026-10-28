extends SceneTree
## Records the real final room's wind phase (phase 3) on hard difficulty (every parry manual) and
## player invincibility OFF, while a scripted player parries every normal/red hit and
## back-dodges gold ones. The production AI fights for DURATION seconds (v0.3: improvised
## combos, gale dash and pull); every strike the improviser picks is logged.
## Run with Godot's movie writer for a video, e.g.:
##   Godot --path game --write-movie out.avi --fixed-fps 60 --resolution 1280x720 \
##         --script tools/record_deer_wind_parry.gd -- <output dir>
## Writes <output dir>/events.json (every hit/parry/guard with times) and contact_NN.png
## snapshots taken on the frame each contact resolves.

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

## Press parry this long (boss action seconds) before a normal/red hit opens.
## K judges immediately; the source-frame windup stays within the shared guard window.
const PARRY_LEAD := 0.20
const DODGE_LEAD := 0.12
const START_DISTANCE := 170.0
const DURATION := 60.0

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var player: LanPlayer
var clash: DeerClashPhase
var output := ""
var current: StringName = &""
var clock := 0.0
var pressed_keys: Dictionary = {}
var events: Array[Dictionary] = []
var snapshots := 0
var _release_parry := false
var _release_dodge := false
var _last_defense := -1
var _last_hp := 0
var _last_poise := 0
var _last_boss_state := -1
var running := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "user://wind_parry"
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("setup")

func setup() -> void:
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	boss = room.deer; player = room.player; clash = boss.clash_phase
	# Reach the wind phase through the real handoffs so the mist field and phase visuals
	# are exactly what a player sees (jumping straight to phase 3 leaves the mist up).
	boss.manual_control = true
	for phase in [1, 2]:
		boss.combat_stats.apply_health_damage(boss.combat_stats.health)
		while boss.phase_transition.active or boss.phase != phase + 1:
			player.combat_stats.restore_health()
			await physics_frame
	while boss.state not in [DeerBoss.State.IDLE, DeerBoss.State.WALK]:
		await physics_frame
	boss.manual_control = false
	_place_player()
	clock = 0.0
	running = true

func _place_player() -> void:
	var center := (boss.world_min_x + boss.world_max_x) * 0.5
	var side := -1.0 if boss.position.x > center else 1.0
	player.reset_after_map_fall(Vector2(boss.position.x + side * START_DISTANCE, boss.position.y))
	player.combat_stats.restore_health()
	player.velocity = Vector2.ZERO
	boss.direction = signf(player.position.x - boss.position.x)

func _physics_process(delta: float) -> bool:
	if not running: return false
	clock += delta
	if _release_parry: Input.action_release(&"parry"); _release_parry = false
	if _release_dodge:
		_key(KEY_L, false); _release_dodge = false
	_log_changes()
	if boss.state == DeerBoss.State.CLASH:
		if current.is_empty():
			current = &"improv"
			pressed_keys.clear()
			events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "combo", "combo": "improv", "branch": -1})
		_log_beat()
		_drive_player()
	else:
		current = &""
		_last_step = -1
	if clock >= DURATION: _finish()
	return false

var _last_step := -1
func _log_beat() -> void:
	if clash.step_index == _last_step or clash.step_index < 0 or clash.step_index >= clash.steps.size(): return
	_last_step = clash.step_index
	events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "beat", "move": String(clash.steps[clash.step_index].move), "distance": absf(player.position.x - boss.position.x)})

## Upcoming hit openings in the current step: [time from now (action s), danger, key].
func _upcoming() -> Array:
	var result := []
	if clash.step_index < 0 or clash.step_index >= clash.steps.size(): return result
	if is_instance_valid(clash.authored):
		var next := clash.authored.next_contact_in()
		var serial := 0
		for row: Dictionary in clash.authored.rows:
			if row.started: serial += 1
		if next >= 0: result.append([next, &"normal", "%d_%d" % [clash.step_index, serial]])
		return result
	for index in clash._hits.size():
		var hit: Dictionary = clash._hits[index]
		if clash._done_hits.has(index): continue
		for entry in clash._plan:
			if entry.clip == hit.clip:
				result.append([float(entry.start) + float(hit.first) / float(entry.fps) - clash.step_time, hit.danger, "%d_%d" % [clash.step_index, index]])
				break
	return result

func _drive_player() -> void:
	for hit in _upcoming():
		var left: float = hit[0]
		var key: String = hit[2]
		if pressed_keys.has(key) or left < 0.0: continue
		if hit[1] == &"gold":
			if left <= DODGE_LEAD:
				pressed_keys[key] = true
				_key(KEY_L, true); _release_dodge = true
				events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "press_dodge", "combo": String(current), "lead": left})
		elif left <= PARRY_LEAD:
			pressed_keys[key] = true
			Input.action_press(&"parry"); _release_parry = true
			events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "press_parry", "combo": String(current), "lead": left, "danger": String(hit[1])})

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _log_changes() -> void:
	var defense := int(player.defense_state)
	var hp := player.combat_stats.health
	var poise := boss.combat_stats.poise
	if defense != _last_defense:
		var name: String = LanPlayer.DefenseState.keys()[defense]
		events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "defense", "state": name, "combo": String(current), "time_scale": Engine.time_scale})
		if name in ["PARRY_SUCCESS", "RED_PARRY_SUCCESS", "PARRY_FAILURE"]: _snapshot(name)
		_last_defense = defense
	if hp < _last_hp:
		events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "player_damage", "amount": _last_hp - hp, "combo": String(current)})
		_snapshot("hit")
	_last_hp = hp
	if poise != _last_poise:
		events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "boss_poise", "poise": poise, "combo": String(current)})
		_last_poise = poise
	if int(boss.state) != _last_boss_state:
		events.append({"t": clock, "f": Engine.get_frames_drawn(), "event": "boss_state", "state": DeerBoss.State.keys()[int(boss.state)], "combo": String(current)})
		_last_boss_state = int(boss.state)
	# Keep the scripted fighter alive and topped up so every combo can be recorded.
	if player.combat_stats.health < 40: player.combat_stats.restore_health(); _last_hp = player.combat_stats.health

func _snapshot(label: String) -> void:
	snapshots += 1
	var path := output.path_join("contact_%02d_%s_%s.png" % [snapshots, String(current), label])
	RenderingServer.frame_post_draw.connect(func() -> void: root.get_texture().get_image().save_png(path), CONNECT_ONE_SHOT)

func _finish() -> void:
	running = false
	var file := FileAccess.open(output.path_join("events.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(events, "  "))
	file.close()
	print("WIND PARRY RECORDING: %d events, %d snapshots, %.1f s" % [events.size(), snapshots, clock])
	quit(0)
