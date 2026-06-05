#!/bin/bash
# Installs Python + Node dependencies so pytest, tsc, eslint, and vitest can
# run in a fresh Claude Code on the web container.
#
# Kept synchronous (no {"async": true} banner) so the agent never starts work
# before dependencies are ready.
set -euo pipefail

# Only run in remote web sessions; local workstations already have deps.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- Python ---------------------------------------------------------------
# --ignore-installed PyJWT works around the Debian-managed PyJWT 2.7.0 that
# pip otherwise refuses to uninstall when supabase/google-auth pull in a
# newer version.
if [ -f requirements.txt ]; then
  pip install --quiet --break-system-packages --ignore-installed PyJWT \
    -r requirements.txt
  pip install --quiet --break-system-packages pytest pytest-asyncio
fi

# --- Node -----------------------------------------------------------------
if [ -f package.json ] && [ ! -d node_modules ]; then
  npm install --no-audit --no-fund --silent
fi
