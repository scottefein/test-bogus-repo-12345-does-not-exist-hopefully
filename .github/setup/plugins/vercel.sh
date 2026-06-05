#!/usr/bin/env bash
# Plugin: vercel
# Creates a Vercel project, links it to the GitHub repo, and sets env vars
#
# Config:
#   framework:        framework preset (e.g. "nextjs")
#   build_command:    build command (e.g. "npm run build")
#   output_directory: output dir (e.g. ".next")
#   env_from_secrets: list of secret keys to set as Vercel env vars

plugin_validate() {
    local token org_id
    token="$(secret_get VERCEL_TOKEN)"
    org_id="$(secret_get VERCEL_TEAM_ID)"

    if [[ -z "$token" ]]; then
        plugin_log "VERCEL_TOKEN not found in secrets"
        return 1
    fi
    if [[ -z "$org_id" ]]; then
        plugin_log "VERCEL_TEAM_ID not found in secrets"
        return 1
    fi

    return 0
}

plugin_run() {
    local token team_id framework build_command output_directory
    token="$(secret_get VERCEL_TOKEN)"
    team_id="$(secret_get VERCEL_TEAM_ID)"
    framework="$(config_get framework)"
    build_command="$(config_get build_command)"
    output_directory="$(config_get output_directory)"

    # Default framework to nextjs
    framework="${framework:-nextjs}"

    plugin_log "Creating Vercel project: $REPO_NAME"

    # Create project with GitHub repo link
    local create_response
    create_response="$(curl -s -X POST "https://api.vercel.com/v10/projects?teamId=$team_id" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg name "$REPO_NAME" \
            --arg framework "$framework" \
            --arg buildCommand "$build_command" \
            --arg outputDirectory "$output_directory" \
            --arg repo "$GITHUB_REPOSITORY" \
            '{
                name: $name,
                framework: $framework,
                buildCommand: $buildCommand,
                outputDirectory: $outputDirectory,
                gitRepository: {
                    type: "github",
                    repo: $repo
                }
            }'
        )" 2>&1)"

    local project_id
    project_id="$(echo "$create_response" | jq -r '.id // empty')"

    if [[ -z "$project_id" ]]; then
        local error_msg
        error_msg="$(echo "$create_response" | jq -r '.error.message // "Unknown error"')"
        plugin_fail "Failed to create Vercel project: $error_msg"
        return 1
    fi

    plugin_log "Vercel project created: $project_id"

    # Set env vars from secrets
    local env_count
    env_count="$(echo "$PLUGIN_CONFIG" | jq -r '.env_from_secrets // [] | length')"

    if [[ "$env_count" -gt 0 ]]; then
        plugin_log "Setting $env_count environment variables on Vercel project"

        # Build env vars array
        local env_payload="[]"
        for i in $(seq 0 $((env_count - 1))); do
            local env_key
            env_key="$(echo "$PLUGIN_CONFIG" | jq -r ".env_from_secrets[$i]")"
            local env_value
            env_value="$(secret_get "$env_key")"

            if [[ -z "$env_value" ]]; then
                plugin_log "WARNING: Secret '$env_key' not found, skipping env var"
                continue
            fi

            env_payload="$(echo "$env_payload" | jq \
                --arg key "$env_key" \
                --arg value "$env_value" \
                '. + [{ key: $key, value: $value, type: "encrypted", target: ["production", "preview", "development"] }]'
            )"
        done

        # Set env vars via API
        local env_response
        env_response="$(curl -s -X POST "https://api.vercel.com/v10/projects/$project_id/env?teamId=$team_id" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$env_payload" 2>&1)"

        plugin_log "Environment variables set"
    fi

    # Set Vercel identifiers as GitHub repo secrets
    plugin_log "Setting VERCEL_PROJECT_ID and VERCEL_TEAM_ID as GitHub secrets"
    gh_set_secret "VERCEL_PROJECT_ID" "$project_id"
    gh_set_secret "VERCEL_TEAM_ID" "$team_id"

    return 0
}
