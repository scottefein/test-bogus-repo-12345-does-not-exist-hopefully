#!/usr/bin/env bash
# Plugin: clerk
# Sets Clerk auth keys as GitHub secrets and Vercel env vars.
# If keys aren't in the GCP secret, sets placeholders that prompt
# the user to replace them after creating a Clerk app in the dashboard.
#
# Config:
#   set_vercel_env:    bool — also set keys as Vercel env vars (default: true)
#   allowed_origins:   list — origins to allow (supports $REPO_NAME substitution)

CLERK_PLACEHOLDER_PK="pk_test_REPLACE_ME_create_app_at_dashboard.clerk.com"
CLERK_PLACEHOLDER_SK="sk_test_REPLACE_ME_create_app_at_dashboard.clerk.com"

plugin_validate() {
    # Always succeeds — we set placeholders if keys are missing
    return 0
}

plugin_run() {
    local secret_key publishable_key
    secret_key="$(secret_get CLERK_SECRET_KEY)"
    publishable_key="$(secret_get NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY)"

    local using_placeholders=false
    if [[ -z "$secret_key" || -z "$publishable_key" ]]; then
        using_placeholders=true
        secret_key="${secret_key:-$CLERK_PLACEHOLDER_SK}"
        publishable_key="${publishable_key:-$CLERK_PLACEHOLDER_PK}"
        plugin_log "Clerk keys not found in secrets — setting placeholders"
        plugin_log "ACTION REQUIRED: Create a Clerk app at https://dashboard.clerk.com"
        plugin_log "Then update these GitHub secrets and Vercel env vars:"
        plugin_log "  - NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY"
        plugin_log "  - CLERK_SECRET_KEY"
    fi

    # Set GitHub repo secrets
    plugin_log "Setting Clerk keys as GitHub secrets"
    gh_set_secret "CLERK_SECRET_KEY" "$secret_key"
    gh_set_secret "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" "$publishable_key"

    # Set Vercel env vars
    local set_vercel_env
    set_vercel_env="$(echo "$PLUGIN_CONFIG" | jq -r '.set_vercel_env // true')"

    if [[ "$set_vercel_env" == "true" ]]; then
        local vercel_token team_id project_id
        vercel_token="$(secret_get VERCEL_TOKEN)"
        team_id="$(secret_get VERCEL_TEAM_ID)"
        project_id="$(secret_get VERCEL_PROJECT_ID)"

        if [[ -n "$vercel_token" && -n "$team_id" && -n "$project_id" ]]; then
            plugin_log "Setting Clerk keys as Vercel env vars"

            local env_payload
            env_payload="$(jq -n \
                --arg pk "$publishable_key" \
                --arg sk "$secret_key" \
                '[
                    { key: "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY", value: $pk, type: "encrypted", target: ["production", "preview", "development"] },
                    { key: "CLERK_SECRET_KEY", value: $sk, type: "encrypted", target: ["production", "preview", "development"] }
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

    # Configure allowed origins on Clerk instance (only if we have real keys)
    if ! $using_placeholders; then
        local origins_count
        origins_count="$(echo "$PLUGIN_CONFIG" | jq -r '.allowed_origins // [] | length')"

        if [[ "$origins_count" -gt 0 ]]; then
            plugin_log "Configuring $origins_count allowed origin(s) on Clerk instance"

            local origins_array="[]"
            for i in $(seq 0 $((origins_count - 1))); do
                local origin
                origin="$(echo "$PLUGIN_CONFIG" | jq -r ".allowed_origins[$i]")"
                origin="${origin//\$REPO_NAME/$REPO_NAME}"
                origins_array="$(echo "$origins_array" | jq --arg o "$origin" '. + [$o]')"
            done

            curl -s -X PATCH "https://api.clerk.com/v1/instance" \
                -H "Authorization: Bearer $secret_key" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --argjson origins "$origins_array" '{allowed_origins: $origins}')" >/dev/null 2>&1

            plugin_log "Allowed origins configured"
        fi
    fi

    return 0
}
