## Headless test runner: every tests/test_*.gd with run(t: TestLog). Exits nonzero on failure.
## A script error stops a test where it stands, and the checks after it never run, so ALL PASS
## also needs: no script errors, every file loaded, every file made at least one check.
## run() may be a coroutine (dialogue walks await Dialogue Manager); autoloads are live.
##   godot --headless -s res://tools/run_tests.gd
extends SceneTree

class ScriptErrors extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

func _initialize() -> void:
	await process_frame  # let autoloads finish _ready
	var errors := ScriptErrors.new()
	OS.add_logger(errors)
	var failed := 0
	var total := 0
	var broken: Array[String] = []
	# `-- only=a,b`: run only test files whose name contains one of these (iteration aid).
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.trim_prefix("only=").split(",", false)
	for f in DirAccess.get_files_at("res://tests"):
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_log.gd":
			continue
		if not only.is_empty() and not Array(only).any(func(o: String) -> bool: return o in f):
			continue
		print("== ", f)
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			broken.append("%s: didn't load" % f)
			continue
		var t := TestLog.new()
		var before := errors.count
		await script.new().run(t)
		failed += t.failures.size()
		total += t.checks
		if errors.count > before:
			broken.append("%s: %d script errors" % [f, errors.count - before])
		elif t.checks == 0:
			broken.append("%s: made no checks" % f)
	OS.remove_logger(errors)
	for b in broken:
		print("  BROKEN ", b)
	failed += broken.size()
	print("\n%d checks, %s" % [total, "ALL PASS" if failed == 0 else "%d FAILED" % failed])
	quit(0 if failed == 0 else 1)
