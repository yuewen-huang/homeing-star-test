extends "../../support/harness.gd"
## LanPlayer's components (restructure P5, 2026-10-19): climbing, vine swinging and the
## ultimate moved out of lan_player.gd into LanClimbing, LanVineSwing and LanUltimate.
## LanPlayer keeps the old names as typed forwarders so rooms, tests and tools still work;
## rooms reset wind and vine regrab through public methods instead of private fields.

func run() -> void:
	use_memory_progress()
	var player := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate() as LanPlayer
	player.world_min_x = -2000.0
	player.world_max_x = 2000.0
	root.add_child(player)
	await process_frame
	check(player.climbing is LanClimbing and player.vine_swing is LanVineSwing and player.ultimate is LanUltimate, "Lan owns her three components")
	check(player.climbing.p == player and player.vine_swing.p == player and player.ultimate.p == player, "Each component reaches back to her")

	player.register_climbable(Rect2(100, 300, 40, 200), -1.0)
	check(player.climbing.climbables == [Rect2(100, 300, 40, 200)] and player.climbing.climb_facings.get(Rect2(100, 300, 40, 200)) == -1.0, "register_climbable still registers through the player")
	player.climb_regrab_block_remaining = 0.2
	check(is_equal_approx(player.climbing.climb_regrab_block_remaining, 0.2), "Climbing state is reachable by its old name")

	player.vine_angle = 0.7
	player.vine_omega = -1.5
	check(is_equal_approx(player.vine_swing.vine_angle, 0.7) and is_equal_approx(player.vine_omega, -1.5), "Vine state forwards both ways")
	var piece := TerrainPiece.new()
	player._vine_regrab_block = piece
	player._vine_regrab_remaining = 0.25
	player.clear_vine_regrab()
	check(player.vine_swing._vine_regrab_block == null and player._vine_regrab_remaining == 0.0, "clear_vine_regrab lets her grab any vine again")
	piece.free()

	player.add_wind(Vector2(120, -40), 3.0)
	check(player._wind != Vector2.ZERO, "Wind pushes her")
	player.clear_wind()
	check(player._wind == Vector2.ZERO and player._wind_accel == 0.0, "clear_wind drops it")

	player.ultimate_window_remaining = 2.5
	check(is_equal_approx(player.ultimate.ultimate_window_remaining, 2.5), "Ultimate state forwards to the component")
	check(not player.ultimate_active and player.ultimate.ultimate_hit_context != null, "The ultimate starts idle with its hit context ready")
	check(is_equal_approx(player.distance_to_segment(Vector2(0, 5), Vector2(-10, 0), Vector2(10, 0)), 5.0), "Forwarded helpers still answer")
	player.free()
	expect_save_untouched()
	finish("LAN COMPONENTS")
