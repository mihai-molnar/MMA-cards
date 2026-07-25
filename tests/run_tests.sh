#!/bin/sh
# Canonical test entry point. Prefer this over invoking run_tests.gd directly.
#
# GDScript has no catchable exceptions: a runtime error inside a suite's
# run() (e.g. a typo'd method call) aborts just that suite silently — the
# runner still reports PASS with exit 0. So on top of the runner's own
# exit code, this script also greps the combined output for the engine's
# own error markers and fails if any are present, even when the exit code
# was 0.
#
# Usage:   tests/run_tests.sh
# Override the Godot binary with: GODOT=/path/to/Godot tests/run_tests.sh

set -u

GODOT_BIN="${GODOT:-/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot}"

cd "$(dirname "$0")/.." || exit 1

# Mandatory: Godot resolves class_name globals through
# .godot/global_script_class_cache.cfg, which only the editor or an
# explicit --import writes, and .godot/ is gitignored. Output discarded —
# only the actual test run's output matters.
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1

output=$("$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd 2>&1)
exit_code=$?

echo "$output"

# Check the exit code first: a genuine load failure already makes the
# runner exit 1 on its own, and reporting that failure once here — not
# again via the marker grep below — keeps the output from double-reporting
# the same problem two different ways.
if [ "$exit_code" -ne 0 ]; then
	echo "run_tests.sh: FAIL (run_tests.gd exited with code $exit_code)"
	exit 1
fi

case "$output" in
	*"SCRIPT ERROR"*|*"Parse Error"*|*"Invalid call"*)
		echo "run_tests.sh: FAIL (engine error marker found in output despite exit code 0)"
		exit 1
		;;
esac

exit 0
