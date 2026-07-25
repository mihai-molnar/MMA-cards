extends SceneTree
class_name TestRunner

## Headless test runner. Auto-discovers suites: any res://tests/suites/test_*.gd
## file is picked up and run, in sorted order — no registration step.
## Preferred entry point: tests/run_tests.sh (also catches runtime script
## errors, which this script alone cannot: GDScript has no catchable
## exceptions, so a runtime error inside a suite's run() silently aborts
## just that suite without failing the run).
## Direct invocation: godot --headless --path . --script res://tests/run_tests.gd

const SUITES_DIR: String = "res://tests/suites"

var _checks: int = 0
var _failures: Array[String] = []
var _current_suite: String = ""

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_record_failure(message)

func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_record_failure("%s — expected %s, got %s" % [message, expected, actual])

func _record_failure(message: String) -> void:
	var line: String = "[%s] %s" % [_current_suite, message]
	_failures.append(line)
	print("  FAIL: %s" % line)

func _discover_suites() -> Array[String]:
	var suite_paths: Array[String] = []
	var file_names: PackedStringArray = DirAccess.get_files_at(SUITES_DIR)
	for file_name: String in file_names:
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			suite_paths.append("%s/%s" % [SUITES_DIR, file_name])
	suite_paths.sort()
	return suite_paths

func _initialize() -> void:
	var suite_paths: Array[String] = _discover_suites()

	if suite_paths.is_empty():
		_current_suite = "discovery"
		_record_failure("No suite files found in %s (expected test_*.gd)" % SUITES_DIR)

	for suite_path: String in suite_paths:
		_current_suite = suite_path.get_file().get_basename()
		print("Running %s" % _current_suite)
		var script: GDScript = load(suite_path)
		if script == null or not script.can_instantiate():
			_record_failure("Failed to load suite script: %s" % suite_path)
			continue
		var suite: RefCounted = script.new()
		if not suite.has_method("run"):
			_record_failure("Suite has no run() method: %s" % suite_path)
			continue
		suite.run(self)

	print("\n%d checks, %d failures" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("PASS")
	else:
		print("FAILED:")
		for failure: String in _failures:
			print("  - %s" % failure)
	quit(0 if _failures.is_empty() else 1)
