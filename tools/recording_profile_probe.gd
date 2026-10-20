extends SceneTree
func _initialize() -> void:
 print("PROFILE_PATH ",OS.get_user_data_dir())
 print("APPDATA ",OS.get_environment("APPDATA"))
 quit()
