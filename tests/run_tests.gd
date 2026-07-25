extends SceneTree
class_name TestRunner

## Headless test runner. Add new suites to SUITES.
## Run: godot --headless --path . --script res://tests/run_tests.gd

const SUITES: Array[String] = [
	"res://tests/suites/test_harness.gd",
]

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

func _initialize() -> void:
	for suite_path: String in SUITES:
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
