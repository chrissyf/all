#!/usr/bin/env bash
#
# Set up the Agent Toolkit for AWS on a developer machine.
#
# Installs the AWS CLI v2, signs in with `aws login`, installs the Agent
# Toolkit (the AWS skills plus the aws-mcp server), and writes the AWS rules
# file into a project that does not already carry one.
#
# macOS and Linux only. Windows uses a PowerShell installer for step 1; see
# the "Windows" section of infra/README.md.
#
# Usage:
#   infra/setup-aws-local.sh [region]        # region defaults to eu-central-1

set -euo pipefail

REGION="${1:-${AWS_SETUP_REGION:-eu-central-1}}"

# The Agent Toolkit control plane is only reachable in us-east-1. This is not
# the region your resources live in, and it must not be swapped for $REGION.
TOOLKIT_REGION="us-east-1"

INSTALLER_URL="https://awscli.amazonaws.com/v2/install.sh"
RULES_URL="https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-agent-rules.md"

step() { printf '\n==> %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
die()  { printf '\nerror: %s\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

step "Checking prerequisites"

case "$(uname -s)" in
  Darwin|Linux) : ;;
  *) die "unsupported OS '$(uname -s)'. On Windows, see infra/README.md." ;;
esac

have curl || die "curl is required. Install it and re-run."

# The installer unpacks a zip on Linux and uses pkgutil on macOS. pkgutil is
# always present; unzip is not.
if [ "$(uname -s)" = "Linux" ] && ! have unzip; then
  die "unzip is required on Linux. Install it and re-run."
fi

curl -fsS --head "$INSTALLER_URL" >/dev/null 2>&1 \
  || die "cannot reach $INSTALLER_URL. Check network access and re-run."

note "OS $(uname -s), arch $(uname -m): ok"

# ---------------------------------------------------------------------------
# 1. AWS CLI v2
# ---------------------------------------------------------------------------

export PATH="$HOME/.local/bin:$PATH"

# `aws login` arrived well after the first v2 releases, so an existing install
# is not automatically good enough. Reinstall when the subcommand is absent.
needs_cli=1
if have aws && aws --version 2>&1 | grep -q '^aws-cli/2\.'; then
  if aws login help >/dev/null 2>&1; then
    needs_cli=0
  else
    note "$(aws --version 2>&1) predates 'aws login'; upgrading"
  fi
fi

if [ "$needs_cli" -eq 1 ]; then
  step "Installing AWS CLI v2"
  curl -fsSL "$INSTALLER_URL" | bash
  hash -r
else
  step "AWS CLI v2 already present"
fi

have aws || die "aws still not on PATH after install. Open a new shell and re-run."
note "$(aws --version 2>&1)"

# Persist the PATH entry the installer relies on, once.
SHELL_RC="$HOME/.bashrc"
[ "$(basename "${SHELL:-/bin/bash}")" = "zsh" ] && SHELL_RC="$HOME/.zshrc"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
touch "$SHELL_RC"
if grep -qF "$PATH_LINE" "$SHELL_RC"; then
  note "PATH already persisted in $SHELL_RC"
else
  printf '\n%s\n' "$PATH_LINE" >> "$SHELL_RC"
  note "PATH persisted to $SHELL_RC"
fi

# ---------------------------------------------------------------------------
# 2. Region and sign in
# ---------------------------------------------------------------------------

step "Setting default region to $REGION"
aws configure set region "$REGION"

# Re-running the whole script should not force a fresh browser round trip.
# Credentials last 12 hours, so a valid session is worth keeping.
if aws sts get-caller-identity >/dev/null 2>&1; then
  step "Existing credentials are still valid; skipping sign in"
else
  step "Signing in to AWS"
  note "A browser window will open. Complete sign in there."
  note "If no browser opens (SSH, no default browser), re-run:"
  note "  aws login --region $REGION --remote"
  aws login --region "$REGION"
fi

# ---------------------------------------------------------------------------
# 3. Verify access
# ---------------------------------------------------------------------------

step "Verifying access"
aws sts get-caller-identity \
  || die "credentials are not working. Re-run 'aws login --region $REGION'."

# ---------------------------------------------------------------------------
# 4. Agent Toolkit
# ---------------------------------------------------------------------------

step "Installing the Agent Toolkit (region $TOOLKIT_REGION)"

# --yes is not accepted by every CLI build, and on a non-interactive stdin the
# wizard bails with 253. Fall back rather than leaving the toolkit uninstalled.
if ! aws configure agent-toolkit --yes --region "$TOOLKIT_REGION"; then
  note "non-interactive install failed; retrying as the interactive wizard"
  aws configure agent-toolkit --region "$TOOLKIT_REGION"
fi

step "Verifying the Agent Toolkit"
aws agent-toolkit list-available-skills --region "$TOOLKIT_REGION" >/dev/null \
  || die "the toolkit did not install cleanly. Re-run this script."
note "skill catalog reachable"

# The aws-mcp server is launched as 'uvx mcp-proxy-for-aws@latest'. Without uv
# the server entry exists but never starts, which is easy to miss.
if have uvx; then
  note "uvx $(uvx --version 2>&1 | awk '{print $2}'): ok"
else
  note "WARNING: uvx not found, so the aws-mcp server cannot start."
  note "         Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

# ---------------------------------------------------------------------------
# 5. Rules file
# ---------------------------------------------------------------------------

step "Checking the AWS rules file"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo_root" ] || repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rules_path="$repo_root/CLAUDE.md"

tmp_rules="$(mktemp)"
trap 'rm -f "$tmp_rules"' EXIT
curl -fsSL -o "$tmp_rules" "$RULES_URL" \
  || die "could not download the rules file from $RULES_URL"

if [ ! -e "$rules_path" ]; then
  cp "$tmp_rules" "$rules_path"
  note "wrote $rules_path"
elif cmp -s "$tmp_rules" "$rules_path"; then
  note "$rules_path already matches upstream"
else
  # Overwriting would discard project instructions that are not ours to drop.
  note "$rules_path exists and differs from upstream; leaving it alone."
  note "Compare with:"
  note "  curl -fsSL $RULES_URL | diff -u $rules_path -"
fi

# ---------------------------------------------------------------------------

step "Done"
note "Credentials are valid for 12 hours, renewable for 90 days without"
note "repeating the browser sign in. Restart your agent session to pick up"
note "the aws-mcp server and the installed skills."
