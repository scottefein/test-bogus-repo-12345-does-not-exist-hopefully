#!/usr/bin/env bash
# Plugin: github-secrets
# Sets GitHub repo secrets from Google Secret Manager values
#
# Config:
#   secrets_to_set: list of secret key names to pull from GCP and set on the repo

plugin_validate() {
    if [[ -z "${SECRETS:-}" ]]; then
        plugin_log "No SECRETS available"
        return 1
    fi

    local secrets_list
    secrets_list="$(echo "$PLUGIN_CONFIG" | jq -r '.secrets_to_set // [] | length')"
    if [[ "$secrets_list" -eq 0 ]]; then
        plugin_log "No secrets_to_set configured"
        return 1
    fi

    return 0
}

plugin_run() {
    local secrets_count
    secrets_count="$(echo "$PLUGIN_CONFIG" | jq -r '.secrets_to_set | length')"

    plugin_log "Setting $secrets_count GitHub repo secrets"

    local failed=0
    for i in $(seq 0 $((secrets_count - 1))); do
        local key
        key="$(echo "$PLUGIN_CONFIG" | jq -r ".secrets_to_set[$i]")"

        local value
        value="$(secret_get "$key")"

        if [[ -z "$value" ]]; then
            plugin_log "WARNING: Secret '$key' not found in GCP secret, skipping"
            continue
        fi

        plugin_log "Setting secret: $key"
        if ! gh_set_secret "$key" "$value"; then
            plugin_log "Failed to set secret: $key"
            failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        plugin_fail "$failed secret(s) failed to set"
        return 1
    fi

    return 0
}
