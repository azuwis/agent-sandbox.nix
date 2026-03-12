#!/usr/bin/env bash
# Network restriction tests
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS=$(uname)

source "$SCRIPT_DIR/lib.sh"

echo "=== Network restriction tests ($OS) ==="
echo

# Build a sandbox with restrictNetwork=true and one allowed domain
SANDBOXED_NET=$(nix-build --no-out-link -E "
  let
    pkgs = import <nixpkgs> { };
    sandbox = import $SCRIPT_DIR/../default.nix { inherit pkgs; };
  in sandbox.mkSandbox {
    pkg = pkgs.bash;
    binName = \"bash\";
    outName = \"sandboxed-bash-net\";
    allowedPackages = [ pkgs.coreutils pkgs.bash pkgs.curl ];
    restrictNetwork = true;
    allowedDomains = [ \"httpbin.org\" ];
  }
")
NET_SHELL="$SANDBOXED_NET/bin/sandboxed-bash-net"
run_net() { "$NET_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

# Test 1: allowed domain works
if run_net 'curl -sf --max-time 10 -o /dev/null http://httpbin.org/get'; then
	echo "PASS: allowed domain (httpbin.org) reachable"
	PASS=$((PASS + 1))
else
	echo "FAIL: allowed domain (httpbin.org) should be reachable"
	FAIL=$((FAIL + 1))
fi

# Test 2: blocked domain fails
if run_net 'curl -sf --max-time 10 -o /dev/null http://example.com'; then
	echo "FAIL: blocked domain (example.com) should be denied"
	FAIL=$((FAIL + 1))
else
	echo "PASS: blocked domain (example.com) denied"
	PASS=$((PASS + 1))
fi

# Test 3: unrestricted mode still works
SANDBOXED_UNRES=$(nix-build --no-out-link -E "
  let
    pkgs = import <nixpkgs> { };
    sandbox = import $SCRIPT_DIR/../default.nix { inherit pkgs; };
  in sandbox.mkSandbox {
    pkg = pkgs.bash;
    binName = \"bash\";
    outName = \"sandboxed-bash-unres\";
    allowedPackages = [ pkgs.coreutils pkgs.bash pkgs.curl ];
    restrictNetwork = false;
  }
")
UNRES_SHELL="$SANDBOXED_UNRES/bin/sandboxed-bash-unres"
run_unres() { "$UNRES_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

if run_unres 'curl -s --max-time 10 -o /dev/null http://example.com'; then
	echo "PASS: unrestricted mode can reach any domain"
	PASS=$((PASS + 1))
else
	echo "FAIL: unrestricted mode should reach any domain"
	FAIL=$((FAIL + 1))
fi

# Test 4: empty allowlist blocks everything
SANDBOXED_BLOCK=$(nix-build --no-out-link -E "
  let
    pkgs = import <nixpkgs> { };
    sandbox = import $SCRIPT_DIR/../default.nix { inherit pkgs; };
  in sandbox.mkSandbox {
    pkg = pkgs.bash;
    binName = \"bash\";
    outName = \"sandboxed-bash-block\";
    allowedPackages = [ pkgs.coreutils pkgs.bash pkgs.curl ];
    restrictNetwork = true;
    allowedDomains = [ ];
  }
")
BLOCK_SHELL="$SANDBOXED_BLOCK/bin/sandboxed-bash-block"
run_block() { "$BLOCK_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

if run_block 'curl -sf --max-time 10 -o /dev/null http://example.com'; then
	echo "FAIL: empty allowlist should block all domains"
	FAIL=$((FAIL + 1))
else
	echo "PASS: empty allowlist blocks all domains"
	PASS=$((PASS + 1))
fi

print_results
exit_status
