extends SceneTree


func _initialize() -> void:
	call_deferred("run_test")


func require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func run_test() -> void:
	var settings := root.get_node("AudioSettings") as AudioSettingsService
	if not require(settings != null, "AudioSettings autoload is missing"):
		return
	for bus_name: StringName in [&"Master", &"Music", &"SFX"]:
		if not require(AudioServer.get_bus_index(bus_name) >= 0, "Audio bus is missing: %s" % bus_name):
			return
		if not require(settings.sliders.has(bus_name), "Settings slider is missing: %s" % bus_name):
			return
	settings.open_settings()
	if not require(settings.settings_panel.visible and paused, "Opening settings did not pause the game"):
		return
	settings.close_settings()
	if not require(not settings.settings_panel.visible and not paused, "Closing settings did not restore the game"):
		return
	print("PASS: audio buses, settings controls, and pause lifecycle")
	quit(0)
