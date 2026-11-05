## Minimal assertion sink for the headless test runner.
class_name TestLog
extends RefCounted

var failures: PackedStringArray = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("  FAIL: ", message)

func eq(got: Variant, expected: Variant, message: String) -> void:
	check(got == expected, "%s (got %s, expected %s)" % [message, got, expected])
