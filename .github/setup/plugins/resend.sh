#!/usr/bin/env bash
# Plugin: resend
# Sets Resend API key and sending domain as GitHub secrets and Vercel env vars.
# Defaults to the shared emails.sefindustries.com API key from GCP secrets.
# If a project-specific RESEND_API_KEY is configured (e.g. for a custom domain),
# it overrides the default.
#
# Config:
#   domain:            Sending domain (default: emails.sefindustries.com)
#   set_vercel_env:    bool — also set keys as Vercel env vars (default: true)

plugin_validate() {
    local api_key
    api_key="$(secret_get RESEND_API_KEY)"

    if [[ -z "$api_key" ]]; then
        plugin_log "RESEND_API_KEY not found in secrets — setting placeholders"
    fi

    return 0
}

plugin_run() {
    local api_key domain
    api_key="$(secret_get RESEND_API_KEY)"
    domain="$(config_get domain)"
    domain="${domain:-emails.sefindustries.com}"

    # Check for a project-specific override key
    local override_key
    override_key="$(secret_get "RESEND_API_KEY_${REPO_NAME^^}")"
    override_key="${override_key:-$(secret_get "RESEND_API_KEY_OVERRIDE")}"

    if [[ -n "$override_key" ]]; then
        plugin_log "Using project-specific Resend API key override"
        api_key="$override_key"
    fi

    local using_placeholders=false
    if [[ -z "$api_key" ]]; then
        using_placeholders=true
        api_key="re_REPLACE_ME_get_key_from_resend_dashboard"
        plugin_log "ACTION REQUIRED: Get an API key from https://resend.com/api-keys"
        plugin_log "Then update RESEND_API_KEY in GitHub secrets and Vercel env vars"
    else
        plugin_log "Using Resend API key for domain: $domain"
    fi

    # Set GitHub secrets
    plugin_log "Setting Resend secrets"
    gh_set_secret "RESEND_API_KEY" "$api_key"
    gh_set_var "RESEND_DOMAIN" "$domain"

    # Set Vercel env vars
    local set_vercel_env
    set_vercel_env="$(echo "$PLUGIN_CONFIG" | jq -r '.set_vercel_env // true')"

    if [[ "$set_vercel_env" == "true" ]]; then
        local vercel_token team_id project_id
        vercel_token="$(secret_get VERCEL_TOKEN)"
        team_id="$(secret_get VERCEL_TEAM_ID)"
        project_id="$(secret_get VERCEL_PROJECT_ID)"

        if [[ -n "$vercel_token" && -n "$team_id" && -n "$project_id" ]]; then
            plugin_log "Setting Resend env vars on Vercel"

            local env_payload
            env_payload="$(jq -n \
                --arg key "$api_key" \
                --arg domain "$domain" \
                '[
                    { key: "RESEND_API_KEY", value: $key, type: "encrypted", target: ["production", "preview", "development"] },
                    { key: "RESEND_DOMAIN", value: $domain, type: "plain", target: ["production", "preview", "development"] }
                ]'
            )"

            curl -s -X POST "https://api.vercel.com/v10/projects/$project_id/env?teamId=$team_id" \
                -H "Authorization: Bearer $vercel_token" \
                -H "Content-Type: application/json" \
                -d "$env_payload" >/dev/null 2>&1

            plugin_log "Vercel env vars set"
        else
            plugin_log "Skipping Vercel env vars (missing VERCEL_TOKEN, VERCEL_TEAM_ID, or VERCEL_PROJECT_ID)"
        fi
    fi

    return 0
}
