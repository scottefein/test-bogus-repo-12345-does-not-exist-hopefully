#!/usr/bin/env bash
# Plugin: supabase
# Creates a Supabase project and sets keys as GitHub secrets and Vercel env vars.
# Falls back to placeholders if SUPABASE_ACCESS_TOKEN isn't available.
#
# Config:
#   organization_id:   Supabase org ID (required for project creation)
#   region:            Project region (default: us-east-1)
#   set_vercel_env:    bool — also set keys as Vercel env vars (default: true)

SUPABASE_API="https://api.supabase.com/v1"

plugin_validate() {
    # Always succeeds — we set placeholders if we can't create
    return 0
}

plugin_run() {
    local access_token org_id region
    access_token="$(secret_get SUPABASE_ACCESS_TOKEN)"
    org_id="$(config_get organization_id)"
    region="$(config_get region)"
    region="${region:-us-east-1}"

    local project_url anon_key service_role_key
    project_url="$(secret_get NEXT_PUBLIC_SUPABASE_URL)"
    anon_key="$(secret_get NEXT_PUBLIC_SUPABASE_ANON_KEY)"
    service_role_key="$(secret_get SUPABASE_SERVICE_ROLE_KEY)"

    # If keys are already in GCP secret, just use them
    if [[ -n "$project_url" && -n "$anon_key" && -n "$service_role_key" ]]; then
        plugin_log "Using existing Supabase keys from secrets"

    # If we have an access token and org, create a new project
    elif [[ -n "$access_token" && -n "$org_id" ]]; then
        plugin_log "Creating Supabase project: $REPO_NAME (region: $region)"

        # Generate a random database password
        local db_pass
        db_pass="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)"

        local create_response
        create_response="$(curl -s -X POST "$SUPABASE_API/projects" \
            -H "Authorization: Bearer $access_token" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg name "$REPO_NAME" \
                --arg org_id "$org_id" \
                --arg region "$region" \
                --arg db_pass "$db_pass" \
                '{
                    name: $name,
                    organization_id: $org_id,
                    region: $region,
                    db_pass: $db_pass
                }'
            )" 2>&1)"

        local project_ref
        project_ref="$(echo "$create_response" | jq -r '.ref // empty')"

        if [[ -z "$project_ref" ]]; then
            local error_msg
            error_msg="$(echo "$create_response" | jq -r '.message // .error // "Unknown error"')"
            plugin_log "Failed to create Supabase project: $error_msg"
            plugin_log "Falling back to placeholders"
            project_url=""
            anon_key=""
            service_role_key=""
        else
            plugin_log "Supabase project created: $project_ref"
            project_url="https://${project_ref}.supabase.co"

            # Store the database password as a secret
            gh_set_secret "SUPABASE_DB_PASSWORD" "$db_pass"

            # Wait for project to be ready before fetching keys
            plugin_log "Waiting for project to initialize..."
            local attempts=0
            local max_attempts=30
            while [[ $attempts -lt $max_attempts ]]; do
                local status
                status="$(curl -s "$SUPABASE_API/projects/$project_ref" \
                    -H "Authorization: Bearer $access_token" | jq -r '.status // empty')"

                if [[ "$status" == "ACTIVE_HEALTHY" ]]; then
                    plugin_log "Project is ready"
                    break
                fi

                attempts=$((attempts + 1))
                if [[ $attempts -ge $max_attempts ]]; then
                    plugin_log "Project still initializing after ${max_attempts} attempts"
                    plugin_log "Keys may not be available yet — check Supabase dashboard"
                    break
                fi
                sleep 10
            done

            # Fetch API keys
            local keys_response
            keys_response="$(curl -s "$SUPABASE_API/projects/$project_ref/api-keys" \
                -H "Authorization: Bearer $access_token" 2>&1)"

            anon_key="$(echo "$keys_response" | jq -r '.[] | select(.name == "anon") | .api_key // empty')"
            service_role_key="$(echo "$keys_response" | jq -r '.[] | select(.name == "service_role") | .api_key // empty')"

            if [[ -z "$anon_key" || -z "$service_role_key" ]]; then
                plugin_log "WARNING: Could not fetch API keys — project may still be initializing"
            else
                plugin_log "API keys retrieved"
            fi
        fi

    # No access token and no pre-configured keys — use placeholders
    else
        plugin_log "No SUPABASE_ACCESS_TOKEN or pre-configured keys found — setting placeholders"
        plugin_log "ACTION REQUIRED: Create a Supabase project at https://supabase.com/dashboard"
        plugin_log "Then update these GitHub secrets and Vercel env vars:"
        plugin_log "  - NEXT_PUBLIC_SUPABASE_URL"
        plugin_log "  - NEXT_PUBLIC_SUPABASE_ANON_KEY"
        plugin_log "  - SUPABASE_SERVICE_ROLE_KEY"
    fi

    # Set values (real or placeholder)
    project_url="${project_url:-https://REPLACE_ME.supabase.co}"
    anon_key="${anon_key:-REPLACE_ME_supabase_anon_key}"
    service_role_key="${service_role_key:-REPLACE_ME_supabase_service_role_key}"

    plugin_log "Setting Supabase keys as GitHub secrets"
    gh_set_secret "NEXT_PUBLIC_SUPABASE_URL" "$project_url"
    gh_set_secret "NEXT_PUBLIC_SUPABASE_ANON_KEY" "$anon_key"
    gh_set_secret "SUPABASE_SERVICE_ROLE_KEY" "$service_role_key"

    # Set Vercel env vars
    local set_vercel_env
    set_vercel_env="$(echo "$PLUGIN_CONFIG" | jq -r '.set_vercel_env // true')"

    if [[ "$set_vercel_env" == "true" ]]; then
        local vercel_token team_id project_id
        vercel_token="$(secret_get VERCEL_TOKEN)"
        team_id="$(secret_get VERCEL_TEAM_ID)"
        project_id="$(secret_get VERCEL_PROJECT_ID)"

        if [[ -n "$vercel_token" && -n "$team_id" && -n "$project_id" ]]; then
            plugin_log "Setting Supabase keys as Vercel env vars"

            local env_payload
            env_payload="$(jq -n \
                --arg url "$project_url" \
                --arg anon "$anon_key" \
                --arg role "$service_role_key" \
                '[
                    { key: "NEXT_PUBLIC_SUPABASE_URL", value: $url, type: "encrypted", target: ["production", "preview", "development"] },
                    { key: "NEXT_PUBLIC_SUPABASE_ANON_KEY", value: $anon, type: "encrypted", target: ["production", "preview", "development"] },
                    { key: "SUPABASE_SERVICE_ROLE_KEY", value: $role, type: "encrypted", target: ["production", "preview", "development"] }
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
