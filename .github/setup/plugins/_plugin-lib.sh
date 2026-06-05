#!/usr/bin/env bash
# Shared helpers for setup plugins
#
# Available in plugin scripts via: source "$PLUGINS_DIR/_plugin-lib.sh"
#
# Environment (set by run-setup.sh):
#   PLUGIN_NAME    — current plugin name
#   PLUGIN_CONFIG  — JSON string of plugin's config block
#   SECRETS        — full JSON blob from Google Secret Manager
#   GITHUB_REPOSITORY, REPO_NAME, REPO_OWNER
#   SETUP_WORKDIR  — temp dir for status/log files
#   GH_TOKEN       — GitHub token for gh CLI

# Extract a value from the SECRETS JSON
# Usage: secret_get <key>
secret_get() {
    local key="$1"
    echo "$SECRETS" | jq -r --arg k "$key" '.[$k] // empty'
}

# Extract a value from the PLUGIN_CONFIG JSON
# Usage: config_get <key>
config_get() {
    local key="$1"
    echo "$PLUGIN_CONFIG" | jq -r --arg k "$key" '.[$k] // empty'
}

# Set a GitHub repo secret
# Usage: gh_set_secret <name> <value>
gh_set_secret() {
    local name="$1" value="$2"
    echo "$value" | gh secret set "$name" --repo "$GITHUB_REPOSITORY"
}

# Set a GitHub repo variable
# Usage: gh_set_var <name> <value>
gh_set_var() {
    local name="$1" value="$2"
    gh variable set "$name" --repo "$GITHUB_REPOSITORY" --body "$value"
}

# Timestamped log to plugin log file and stdout
# Usage: plugin_log <msg>
plugin_log() {
    local msg="$1"
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local line="[$ts] [$PLUGIN_NAME] $msg"
    echo "$line"
    echo "$line" >> "$SETUP_WORKDIR/$PLUGIN_NAME.log"
}

# Log error and return 1
# Usage: plugin_fail <msg>
plugin_fail() {
    local msg="$1"
    plugin_log "FAIL: $msg"
    return 1
}
