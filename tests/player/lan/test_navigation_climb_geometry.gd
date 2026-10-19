extends SceneTree

## 导航馆红线区域的关卡几何回归检查。
## 用法：homeing-star-test/run-tests.ps1 -Test test_navigation_climb_geometry

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred(&"run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  [ ok ] ", message)
	else:
		failures += 1
		print("  [FAIL] ", message)


func run() -> void:
	var town := (load("res://scenes/levels/town/homeward_town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	await process_frame

	var world := town.get("world_root") as Node2D
	var player := town.get("player") as CharacterBody2D
	var geometry := world.get_node_or_null("NavigationClimbGeometry") as Node2D
	check(geometry != null, "导航馆有独立的攀爬关卡几何")
	if geometry == null:
		finish(town)
		return

	var left_wall := geometry.get_node_or_null("LeftClimbWall") as StaticBody2D
	var right_wall := geometry.get_node_or_null("RightClimbWall") as StaticBody2D
	var second_floor := geometry.get_node_or_null("SecondFloorSurface") as Marker2D
	check(left_wall != null and right_wall != null, "主立面左右两侧都有墙碰撞")
	check(second_floor != null, "横向石梁有二楼站立面标记")
	check(left_wall != null and left_wall.is_in_group(&"climbable_wall"), "左墙可被攀爬机制按组检索")
	check(right_wall != null and right_wall.is_in_group(&"climbable_wall"), "右墙可被攀爬机制按组检索")
	check(second_floor != null and second_floor.is_in_group(&"second_floor_surface"),
		"二楼地面可被任务/扒边机制按组检索")

	var floor_y := float(geometry.get_meta(&"second_floor_y"))
	var left_x := float(geometry.get_meta(&"left_x"))
	var right_x := float(geometry.get_meta(&"right_x"))
	check(floor_y < SideviewMapLayout.GROUND_BASELINE_Y, "二楼地面位于主街上方")
	check(right_x > left_x, "二楼地面从左墙延伸到右墙")

	# 站到横梁范围内且脚在顶面上方时，玩家的自定义落地系统必须吸附到二楼。
	player.position = Vector2((left_x + right_x) * 0.5, floor_y - 4.0)
	var resolved_floor := float(player.call(&"resolve_ground_snap_y"))
	check(is_equal_approx(resolved_floor, floor_y), "玩家落地系统能解析到二楼站立面")

	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	check(sprite.sprite_frames.get_frame_count(&"ledge_hang") == 6, "抓边动画接入 6 帧素材")
	check(sprite.sprite_frames.get_frame_count(&"ledge_hang_idle") == 6, "挂边待机接入 6 帧素材")
	check(sprite.sprite_frames.get_frame_count(&"ledge_climb") == 8, "翻上二楼动画接入 8 帧素材")
	player.call(&"start_ledge_grab", left_x, floor_y, -1.0)
	check(sprite.animation == &"ledge_hang", "抓到左墙边缘后播放 hang")
	player.call(&"on_animation_finished")
	check(sprite.animation == &"ledge_hang_idle", "hang 播完切入循环待机")
	player.call(&"start_ledge_climb")
	check(sprite.animation == &"ledge_climb", "挂边时可进入 up 翻越动画")
	player.call(&"finish_ledge_climb")
	check(is_equal_approx(player.position.y, floor_y), "翻越结束后脚底准确落在二楼地面")

	# 墙底必须高于站立角色头顶，保证沿街走过正门时不被侧墙卡住。
	if left_wall != null:
		var collision := left_wall.get_node("CollisionShape2D") as CollisionShape2D
		var rect := collision.shape as RectangleShape2D
		var wall_bottom := left_wall.position.y + rect.size.y * 0.5
		check(wall_bottom <= SideviewMapLayout.GROUND_BASELINE_Y - 58.0,
			"墙碰撞给主街保留至少一个角色高度的通行净空")

	finish(town)


func finish(town: Node) -> void:
	print("")
	print("结果：%d 项检查，%d 项失败" % [checks, failures])
	town.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
