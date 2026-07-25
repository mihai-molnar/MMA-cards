extends RefCounted

## Proves the runner counts checks and compares values correctly.
func run(t) -> void:
	t.check(true, "check() accepts a true condition")
	t.check_eq(2 + 2, 4, "check_eq() compares equal integers")
	t.check_eq("jab", "jab", "check_eq() compares equal strings")
