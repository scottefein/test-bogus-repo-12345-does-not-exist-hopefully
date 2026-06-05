#!/usr/bin/env bash
# Post-creation setup orchestrator
# Runs enabled plugins from .github/setup/plugins/
#
# Environment:
#   SETUP_CONFIG — JSON string with setup configuration
#   SECRETS      — JSON blob from Google Secret Manager
#   GH_TOKEN     — GitHub token for gh CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins"
SETUP_WORKDIR="$(mktemp -d)"
export SETUP_WORKDIR

# Parse config
if [[ -z "${SETUP_CONFIG:-}" ]]; then
    echo "::error::SETUP_CONFIG is not set"
    exit 1
fi

enabled="$(echo "$SETUP_CONFIG" | jq -r '.enabled // false')"
if [[ "$enabled" != "true" ]]; then
    echo "::notice::Setup is disabled in config. Exiting."
    exit 0
fi

plugin_count="$(echo "$SETUP_CONFIG" | jq -r '.plugins | length')"
if [[ "$plugin_count" -eq 0 ]]; then
    echo "::notice::No plugins configured. Exiting."
    exit 0
fi

# Export common vars
export REPO_OWNER="${GITHUB_REPOSITORY%%/*}"
export REPO_NAME="${GITHUB_REPOSITORY##*/}"

echo "=== Post-Creation Setup ==="
echo "Repository: $GITHUB_REPOSITORY"
echo "Plugins: $plugin_count"
echo ""

# Track results
declare -A PLUGIN_RESULTS

for i in $(seq 0 $((plugin_count - 1))); do
    plugin_name="$(echo "$SETUP_CONFIG" | jq -r ".plugins[$i].name")"
    plugin_config="$(echo "$SETUP_CONFIG" | jq -c ".plugins[$i].config // {}")"
    plugin_script="$PLUGINS_DIR/${plugin_name}.sh"

    echo "--- Plugin: $plugin_name ---"

    if [[ ! -f "$plugin_script" ]]; then
        echo "::warning::Plugin script not found: $plugin_script"
        PLUGIN_RESULTS["$plugin_name"]="skipped (not found)"
        continue
    fi

    # Export plugin-specific env
    export PLUGIN_NAME="$plugin_name"
    export PLUGIN_CONFIG="$plugin_config"

    # Source the plugin library and plugin script in a subshell
    # Use || true to prevent set -e from killing the orchestrator on plugin failure
    (
        source "$PLUGINS_DIR/_plugin-lib.sh"
        source "$plugin_script"

        # Validate
        if ! plugin_validate; then
            plugin_log "Validation failed, skipping"
            exit 2
        fi

        # Run
        if ! plugin_run; then
            plugin_log "Execution failed"
            exit 1
        fi

        plugin_log "Completed successfully"
    ) && rc=0 || rc=$?

    case $rc in
        0) PLUGIN_RESULTS["$plugin_name"]="success" ;;
        2) PLUGIN_RESULTS["$plugin_name"]="skipped (validation failed)" ;;
        *) PLUGIN_RESULTS["$plugin_name"]="failed" ;;
    esac
done

# Print summary
echo ""
echo "=== Setup Summary ==="
any_failed=false
for name in "${!PLUGIN_RESULTS[@]}"; do
    status="${PLUGIN_RESULTS[$name]}"
    echo "  $name: $status"
    if [[ "$status" == "failed" ]]; then
        any_failed=true
    fi
done

if $any_failed; then
    echo "::warning::One or more plugins failed. Check logs above."
fi

echo "=== Setup Complete ==="
