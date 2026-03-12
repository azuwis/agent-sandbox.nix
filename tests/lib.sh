#!/usr/bin/env bash
# Shared test utilities

PASS=0
FAIL=0

expect_ok() {
	local desc="$1"
	shift
	if run "$*"; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc (should have succeeded)"
		FAIL=$((FAIL + 1))
	fi
}

expect_fail() {
	local desc="$1"
	shift
	if run "$*"; then
		echo "FAIL: $desc (should have been denied)"
		FAIL=$((FAIL + 1))
	else
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	fi
}

print_results() {
	echo
	echo "=== Results: $PASS passed, $FAIL failed ==="
}

exit_status() {
	[ "$FAIL" -eq 0 ]
}
