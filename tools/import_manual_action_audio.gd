extends SceneTree
const STAGING := "D:/HomingStar/Art/manual-action-audio-20261011/"
const DEST := "res://assets/shared/audio/actions/"
func _initialize() -> void:
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string(STAGING+"manifest.json"))
	for row in manifest:
		var stream := AudioStreamWAV.load_from_file(STAGING+row.key+".wav", {"compress/mode":2})
		assert(stream != null)
		assert(stream.format == AudioStreamWAV.FORMAT_QOA, "Expected native QOA compression")
		if row.key == "deer_run":
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0; stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
		assert(ResourceSaver.save(stream,DEST+row.key+".res") == OK)
		print(row.key, ": ", stream.data.size(), " bytes; ", stream.get_length(), " s")
	quit()
