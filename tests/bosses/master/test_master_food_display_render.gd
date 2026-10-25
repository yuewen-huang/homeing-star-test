extends "../../support/harness.gd"
## GPU readback only; no production screenshots or visual acceptance judgments.
func frame_image() -> Image:
	for i in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func changed_pixels(before: Image, after: Image) -> int:
	var count := 0
	for y in range(0,after.get_height(),2):
		for x in range(0,after.get_width(),2):
			var a := before.get_pixel(x,y)
			var b := after.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.1: count += 1
	return count

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false,"UI render regression requires -Visual")
		finish("MASTER FOOD DISPLAY RENDER")
		return
	use_memory_progress()
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(2)
	dev.select_combo_library(9)
	dev.play_action(4)
	dev.process_mode = Node.PROCESS_MODE_DISABLED
	var food: MasterFoodMechanism = dev.adapter.master.food_mechanism
	food.begin_collect()
	var display := food.display
	display.clear()
	var baseline := await frame_image()
	food._refresh_display()
	display.countdown.hide()
	var bubble := await frame_image()
	check(changed_pixels(baseline,bubble) > 150,"The requested food icon bubble draws over the actual room")
	display.bubble.hide()
	display.countdown.show()
	var timer := await frame_image()
	check(changed_pixels(baseline,timer) > 300,"Numeric ring countdown is visible in screen space below the developer toolbar")
	food.remaining = 0.2
	food.selected = food.wanted
	food.bag[food.wanted] = 1
	dev.player.global_position = dev.adapter.master.global_position
	food.advance(0.01)
	check(display.countdown.digits.text == "20" and is_equal_approx(display.countdown.seconds,20),"Delivery refills the actual countdown display for the next request")
	var next_round := await frame_image()
	check(changed_pixels(timer,next_round) > 150,"Next round redraws its icon and refreshed countdown")
	food.fail()
	food._refresh_display()
	check(not display.bubble.visible and not display.countdown.visible,"Failure removes both UI elements without a text prompt")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER FOOD DISPLAY RENDER")
