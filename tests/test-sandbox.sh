#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS=$(uname)
# Build a sandboxed shell — same shape as a real agent wrapper
# but using bash so we can run arbitrary test commands inside.
# Build a minimal sandbox (no stateDirs/stateFiles) for isolation tests
SANDBOXED=$(nix-build --no-out-link -E "
  let
    pkgs = import <nixpkgs> { };
    sandbox = import $SCRIPT_DIR/../default.nix { inherit pkgs; };
  in sandbox.mkSandbox {
    pkg = pkgs.bash;
    binName = \"bash\";
    outName = \"sandboxed-bash\";
    allowedPackages = [ pkgs.coreutils pkgs.bash ];
    stateDirs = [ ];
  }
")
SHELL="$SANDBOXED/bin/sandboxed-bash"
run_sandboxed() {
	"$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1
}

# Build a sandbox WITH stateDirs, stateFiles, and extraEnv for feature tests
SANDBOXED_WITH_STATE=$(nix-build --no-out-link -E "
  let
    pkgs = import <nixpkgs> { };
    sandbox = import $SCRIPT_DIR/../default.nix { inherit pkgs; };
  in sandbox.mkSandbox {
    pkg = pkgs.bash;
    binName = \"bash\";
    outName = \"sandboxed-bash-state\";
    allowedPackages = [ pkgs.coreutils pkgs.bash ];
    stateDirs = [ \"\\\$HOME/.test-state-dir\" ];
    stateFiles = [ \"\\\$HOME/.test-state-file\" ];
    extraEnv = { TEST_VAR = \"test-value\"; };
  }
")
SHELL_WITH_STATE="$SANDBOXED_WITH_STATE/bin/sandboxed-bash-state"
run_sandboxed_state() {
	"$SHELL_WITH_STATE" --norc --noprofile -c "$@" >/dev/null 2>&1
}
# Capture output variant for extraEnv test
run_sandboxed_state_output() {
	"$SHELL_WITH_STATE" --norc --noprofile -c "$@" 2>/dev/null
}
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"
PASS=0
FAIL=0
expect_fail() {
	local desc="$1"
	shift
	if run_sandboxed "$*"; then
		echo "FAIL: $desc (should have been denied)"
		FAIL=$((FAIL + 1))
	else
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	fi
}
expect_ok() {
	local desc="$1"
	shift
	if run_sandboxed "$*"; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc (should have succeeded)"
		FAIL=$((FAIL + 1))
	fi
}
echo "=== Sandbox isolation tests ($OS) ==="
echo
# --- Should be denied on both platforms ---
expect_fail "cannot read ~/.ssh" "ls \$HOME/.ssh"
expect_fail "cannot read ~/.bash_history" "cat \$HOME/.bash_history"
expect_fail "cannot write to /nix/store" "touch /nix/store/test"
expect_fail "cannot read /root" "ls /root"
# --- Should be allowed on both platforms ---
expect_ok "can write to CWD" "touch ./sandbox-test-file && rm ./sandbox-test-file"
expect_ok "can write to /tmp" "touch /tmp/sandbox-test && rm /tmp/sandbox-test"
expect_ok "can read /etc/resolv.conf" "cat /etc/resolv.conf > /dev/null"
expect_ok "can run allowed binaries" "ls / > /dev/null"
# --- Platform-specific ---
if [ "$OS" = "Darwin" ]; then
	# Seatbelt denies writes to /etc
	expect_fail "cannot write to /etc" "touch /etc/test"
	# HOME itself is readable (traversal allow) but not writable
	expect_ok "can read home dir (traversal)" "ls \$HOME > /dev/null"
	expect_fail "cannot write to home" "touch \$HOME/.test-write"
elif [ "$OS" = "Linux" ]; then
	# bwrap builds the mount tree from scratch — /etc is an implicit
	# writable tmpfs (only specific files are ro-bind mounted in).
	# Writes "succeed" but are ephemeral and never touch the host.
	expect_ok "/etc is writable tmpfs (ephemeral, not host)" "touch /etc/test && rm /etc/test"
	# Verify that host /etc content is NOT leaked (only explicit ro-binds exist)
	expect_fail "cannot read host /etc/shadow" "cat /etc/shadow"
	# $HOME is an intentional writable tmpfs — host dotfiles are hidden,
	# but scratch writes are allowed (lost on exit).
	expect_ok "home is empty tmpfs" "ls \$HOME"
	expect_ok "home tmpfs is writable (ephemeral)" "touch \$HOME/.test-write && rm \$HOME/.test-write"
	# Verify host home content is hidden
	expect_fail "host dotfiles are not visible" "ls \$HOME/.bashrc"
fi
echo
echo "=== stateDirs / stateFiles / extraEnv tests ($OS) ==="
echo

# Helper that uses the state-enabled sandbox
expect_ok_state() {
	local desc="$1"
	shift
	if run_sandboxed_state "$*"; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc (should have succeeded)"
		FAIL=$((FAIL + 1))
	fi
}

expect_fail_state() {
	local desc="$1"
	shift
	if run_sandboxed_state "$*"; then
		echo "FAIL: $desc (should have been denied)"
		FAIL=$((FAIL + 1))
	else
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	fi
}

# Test stateDirs: should be able to write to configured state directory
expect_ok_state "can write to stateDir" "echo test > \$HOME/.test-state-dir/file && cat \$HOME/.test-state-dir/file"

# Test stateFiles: should be able to write to configured state file
expect_ok_state "can write to stateFile" "echo test > \$HOME/.test-state-file && cat \$HOME/.test-state-file"

# Test extraEnv: environment variable should be accessible
if [ "$(run_sandboxed_state_output 'echo $TEST_VAR')" = "test-value" ]; then
	echo "PASS: extraEnv variable is accessible"
	PASS=$((PASS + 1))
else
	echo "FAIL: extraEnv variable not accessible or wrong value"
	FAIL=$((FAIL + 1))
fi

# Test that non-configured paths are still denied in state sandbox
expect_fail_state "stateDir sandbox still denies ~/.ssh" "ls \$HOME/.ssh"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
