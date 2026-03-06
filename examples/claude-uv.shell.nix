# Example: a dev shell with a sandboxed Claude Code binary and uv for Python.
# Handles NixOS dynamic linking so that uv-managed packages (e.g. matplotlib)
# work correctly without uv trying to manage its own Python installation.
#
# NixOS users: make sure nix-ld is enabled in your configuration.nix:
#   programs.nix-ld.enable = true;
#
# Usage:
#   export CLAUDE_CODE_OAUTH_TOKEN="your_token_here"
#   nix-shell examples/claude-uv.shell.nix
let
  pkgs = import <nixpkgs> { config.allowUnfree = true; };
  sandbox = import (fetchTarball
    "https://github.com/archie-judd/agent-sandbox.nix/archive/main.tar.gz") {
      pkgs = pkgs;
    };

  # These libraries are threaded into LD_LIBRARY_PATH so that nix-ld can
  # satisfy dynamic link dependencies (libstdc++, zlib, libX11) for any
  # compiled wheels uv installs at runtime.
  dynamicLibraries = [ pkgs.stdenv.cc.cc pkgs.zlib pkgs.xorg.libX11 ];

  # Preserve the host LD_LIBRARY_PATH (set by nix-ld) and prepend our libs.
  # Dropping the host value would break glibc resolution for nix-ld itself.
  ldLibraryPath = "${builtins.getEnv "LD_LIBRARY_PATH"}:${
      pkgs.lib.makeLibraryPath dynamicLibraries
    }";

in if pkgs.stdenv.isLinux then
  let
    claude-sandboxed = sandbox.mkSandbox {
      pkg = pkgs.claude-code;
      binName = "claude";
      outName = "claude-sandboxed";
      stateDirs = [ "$HOME/.claude" "$HOME/.cache/uv" "$HOME/.local/share/uv" ];
      stateFiles = [ "$HOME/.claude.json" ];
      allowedPackages = [
        pkgs.coreutils
        pkgs.bash
        pkgs.git
        pkgs.ripgrep
        pkgs.fd
        pkgs.gnused
        pkgs.gnugrep
        pkgs.findutils
        pkgs.jq
        pkgs.uv
        pkgs.python3
      ];
      extraEnv = {
        CLAUDE_CODE_OAUTH_TOKEN = "$CLAUDE_CODE_OAUTH_TOKEN";
        GIT_AUTHOR_NAME = "claude-agent";
        GIT_AUTHOR_EMAIL = "claude-agent@localhost";
        GIT_COMMITTER_NAME = "claude-agent";
        GIT_COMMITTER_EMAIL = "claude-agent@localhost";
        UV_NO_MANAGED_PYTHON = "1";
        LD_LIBRARY_PATH = ldLibraryPath;
      };
    };
  in pkgs.mkShell {
    packages = [ pkgs.uv pkgs.python3 claude-sandboxed ];
    UV_NO_MANAGED_PYTHON = "1";
    LD_LIBRARY_PATH = ldLibraryPath;
  }

else if pkgs.stdenv.isDarwin then
# On macOS, uv can use its own managed Python without the NixOS linker
# workaround, so we skip the pythonWithTkinter and LD_LIBRARY_PATH setup.
  let
    claude-sandboxed = sandbox.mkSandbox {
      pkg = pkgs.claude-code;
      binName = "claude";
      outName = "claude-sandboxed";
      stateDirs = [ "$HOME/.claude" "$HOME/.cache/uv" "$HOME/.local/share/uv" ];
      stateFiles = [ "$HOME/.claude.json" ];
      allowedPackages = [
        pkgs.coreutils
        pkgs.bash
        pkgs.git
        pkgs.ripgrep
        pkgs.fd
        pkgs.gnused
        pkgs.gnugrep
        pkgs.findutils
        pkgs.jq
        pkgs.uv
      ];
      extraEnv = {
        CLAUDE_CODE_OAUTH_TOKEN = "$CLAUDE_CODE_OAUTH_TOKEN";
        GIT_AUTHOR_NAME = "claude-agent";
        GIT_AUTHOR_EMAIL = "claude-agent@localhost";
        GIT_COMMITTER_NAME = "claude-agent";
        GIT_COMMITTER_EMAIL = "claude-agent@localhost";
      };
    };
  in pkgs.mkShell { packages = [ pkgs.uv pkgs.python3 claude-sandboxed ]; }

else
  throw "Unsupported platform: ${pkgs.stdenv.hostPlatform.system}"
