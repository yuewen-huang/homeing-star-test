extends SceneTree
## Shared scaffolding for test scripts (restructure P2, 2026-10-19). A test extends this file
## by relative path (`extends "../support/harness.gd"`, one `../` per folder level),
## implements `run()`, and ends with `finish("NAME")`. (Not named `test_*`: run-tests.ps1 would
## run it as a test.)
##
##   func run() -> void:
##       var progress := use_memory_progress()
##       ...
##       check(value == 3, "Three hits land")
##       expect_save_untouched()
##       finish("MY FEATURE")
##
## run-tests.ps1 passes a test when it exits 0 and prints no SCRIPT ERROR, so `finish()` exits
## 1 when any check failed.

## A save service that keeps everything in memory, never writes the player's save, and
## unlocks every ability unless one is listed in `locked`.
class MemoryProgress extends SaveProgressService:
	var locked: Array[StringName] = []
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass
	func is_ability_unlocked(ability: StringName) -> bool: return not locked.has(ability)

var checks := 0
var failures := 0
var _save_existed := false
var _save_bytes := PackedByteArray()

func _initialize() -> void: call_deferred("run")

## Override with the test body.
func run() -> void:
	push_error("Test script does not implement run()")
	finish("UNIMPLEMENTED")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + message)

## Swaps the SaveProgress autoload for a MemoryProgress and remembers the real save file's
## bytes for expect_save_untouched().
func use_memory_progress() -> MemoryProgress:
	_save_existed = FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	_save_bytes = FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if _save_existed else PackedByteArray()
	var previous := root.get_node_or_null("SaveProgress")
	if previous:
		root.remove_child(previous)
		previous.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	return memory

## The player's real save is exactly as use_memory_progress() found it.
func expect_save_untouched() -> void:
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == _save_existed, "Save existence unchanged")
	if _save_existed:
		check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == _save_bytes, "Save file byte-identical")

func wait_frames(count: int) -> void:
	for i in count: await process_frame

## Prints the summary and quits: exit code 1 when any check failed.
func finish(label: String) -> void:
	print("%s: %d checks, %d failures" % [label, checks, failures])
	quit(1 if failures else 0)
