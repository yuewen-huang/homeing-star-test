extends RefCounted
## Capture-process-only mix. No AudioSettings API, config write, resource save,
## or production constant is touched. Buses disappear when this process exits.
static func apply(tree: SceneTree) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), true)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), -3.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Master"), -3.0)
	var index := AudioServer.get_bus_index(&"RecordingParry")
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, &"RecordingParry")
	AudioServer.set_bus_send(index, &"Master")
	AudioServer.set_bus_volume_db(index, 3.0)
	var feedback := tree.root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.parry_player.bus = &"RecordingParry"
