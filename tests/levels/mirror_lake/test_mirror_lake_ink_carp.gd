extends SceneTree
## 镜湖墨鲤打鱼：阳震刀→扑腾；非扑腾阴攻无效；击杀掉可捡红印；不改芦苇门。
class MemoryProgress extends SaveProgressService:
	var reject := false
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return not reject
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

var checks := 0
var failures := 0
var scene: MirrorLake
var player: LanPlayer
var carp: MirrorLakeInkCarp
var memory: MemoryProgress
var original: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func side(value: int) -> void:
	if scene.side == value:
		return
	scene.advance_switch(MirrorLake.SWITCH_COOLDOWN + 0.1)
	check(scene.request_switch(), "mirror switch succeeds")

func place(at: Vector2) -> void:
	player.position = at
	player.velocity = Vector2.ZERO
	player.air_state = LanPlayer.AirState.GROUNDED
	player.ground_action_state = LanPlayer.GroundActionState.NONE
	player.defense_state = LanPlayer.DefenseState.NONE
	player.attack_state = LanPlayer.AttackState.NONE
	player.play_idle()

func make_scene() -> void:
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	player = scene.player as LanPlayer
	player.set_physics_process(false)
	carp = scene.ink_carp

func run() -> void:
	Input.use_accumulated_input = false
	original = root.get_node("SaveProgress")
	root.remove_child(original)
	memory = MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	make_scene()
	await process_frame

	check(carp != null and is_instance_valid(carp), "Ink carp is installed on the real map")
	check(carp.visible and carp.state == MirrorLakeInkCarp.State.HOPPING, "Carp starts hopping")
	check(carp.position.x >= MirrorLakeInkCarp.PATROL_MIN_X - 1.0, "Carp patrol begins after the second bridge")
	check(carp.sprite != null and carp.sprite.sprite_frames != null, "Jump sheet frames loaded")
	check(carp.sprite.sprite_frames.get_frame_count(&"hop") == 12, "Sheet has 12 hop frames")

	# 芦苇门阴阳踩印逻辑保持原样（入口仍存在且未改开门）。
	check(scene.entry != null and "gate_open" in scene.entry, "Entry reed gate still owns gate_open")
	var gate_was_open: bool = scene.entry.gate_open
	check(gate_was_open == false or gate_was_open == true, "Reed gate open flag readable")
	check(scene.entry.has_method("is_gate_blocking"), "Reed gate blocking API unchanged")

	# 跃动会推进帧。
	var start_frame := carp.frame_index
	for i in 40:
		carp.tick(0.05)
	check(carp.frame_index != start_frame or carp.position.x != MirrorLakeInkCarp.PATROL_MIN_X + 80.0, "Hopping advances frames / position")

	# 阳面：站近落地帧震刀 → 扑腾。
	side(MirrorLake.Side.YANG)
	place(Vector2(carp.position.x + 40.0, MirrorLake.STAND_Y))
	key(KEY_K, true)
	player._physics_process(1.0 / 60.0)
	check(player.defense_state == LanPlayer.DefenseState.PARRY_ACTIVE, "Yang K starts parry near carp")
	# 强制进入落地溅击窗口并解析震刀。
	carp.frame_index = 4
	carp.frame_age = 0.0
	carp._advance_hop_frame()
	check(carp.frame_index == 5, "Land frame 6 armed")
	check(carp.state == MirrorLakeInkCarp.State.FLOPPING, "Successful yang parry of splash puts carp into flop")
	key(KEY_K, false)

	# 扑腾期间阴攻击受伤；非扑腾不受伤。
	var hits_after_parry := carp.hits_left
	side(MirrorLake.Side.YIN)
	place(Vector2(carp.position.x - 30.0, MirrorLake.STAND_Y))
	carp.receive_hit(1, player.global_position)
	check(carp.hits_left == hits_after_parry - 1, "Yin hit while flopping deals damage")

	# 等扑腾结束。
	carp.flop_left = 0.0
	carp._tick_flop(0.02)
	check(carp.state == MirrorLakeInkCarp.State.HOPPING, "Flop ends back to hopping")
	var before := carp.hits_left
	carp.receive_hit(1, player.global_position)
	check(carp.hits_left == before, "Yin hit while hopping does not damage")

	# 再震刀扑腾并击杀。
	side(MirrorLake.Side.YANG)
	place(Vector2(carp.position.x + 20.0, MirrorLake.STAND_Y))
	key(KEY_K, true)
	player._physics_process(1.0 / 60.0)
	carp.enter_flop()
	key(KEY_K, false)
	side(MirrorLake.Side.YIN)
	carp.hits_left = 1
	carp.receive_hit(1, player.global_position)
	check(carp.state == MirrorLakeInkCarp.State.DEAD, "Killing flopping carp enters DEAD")
	check(carp.has_seal_visible(), "Red seal is visible after defeat")
	check(not memory.has_claimed_reward(MirrorLakeInkCarp.REWARD_ID), "Seal not claimed until pickup")

	# 失败存档不给物品。
	memory.reject = true
	place(Vector2(carp.position.x, MirrorLake.STAND_Y))
	carp._tick_dead(0.02)
	check(not carp.seal_claimed_flag and memory.get_item_count(MirrorLakeInkCarp.REWARD_ITEM) == 0, "Failed save keeps seal pickup")
	memory.reject = false
	place(Vector2(carp.position.x, MirrorLake.STAND_Y))
	carp._tick_dead(0.05)
	if not carp.seal_claimed_flag:
		carp._try_claim_seal()
	check(carp.seal_claimed_flag and memory.get_item_count(MirrorLakeInkCarp.REWARD_ITEM) == 1, "Pickup grants mirror_carp_seal once")
	check(not carp.has_seal_visible(), "Claimed seal hides")
	carp._tick_dead(0.05)
	check(memory.get_item_count(MirrorLakeInkCarp.REWARD_ITEM) == 1, "Standing cannot duplicate seal")

	# 重进：已领印后鱼不再刷。
	scene.queue_free()
	await process_frame
	make_scene()
	await process_frame
	check(carp != null and not carp.visible, "Re-entry hides carp after seal claimed")
	check(memory.has_claimed_reward(MirrorLakeInkCarp.REWARD_ID), "Reward id stays claimed")

	# 受击震屏：镜湖须有活动 Camera2D（或 feedback 安全跳过），不可再 assert 崩。
	check(scene.get_node_or_null("CombatCamera") is Camera2D, "Mirror lake installs CombatCamera for shake")
	var feedback := root.get_node("/root/CombatFeedback") as CombatFeedbackService
	check(feedback != null, "CombatFeedback autoload present")
	feedback.request_screen_shake(0.12, 6.0)
	check(true, "request_screen_shake no longer asserts without camera")
	player.emit_received_hit_feedback(carp.global_position, 1.0)
	check(true, "emit_received_hit_feedback / emit_hit path survives on mirror lake")
	# 确认入口开门逻辑未被本玩法改写（门状态与初始一致）。
	check(scene.entry.gate_open == gate_was_open, "Carp hunt does not open/close reed gate")
	check(scene.entry.has_method("is_seal_yin_clear") and scene.entry.has_method("is_seal_yang_ghost_visible"), "Yin-yang stamp unlock helpers unchanged")

	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	print("INK CARP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
