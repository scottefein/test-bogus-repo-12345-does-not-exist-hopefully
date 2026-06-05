#!/usr/bin/env bash
# Shared functions for sef-industries-team sync tooling

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/src"
AGENTS_SRC="$SRC_DIR/agents"
TEMPLATE_DIR="$SRC_DIR/templates"
AGENTS_OUT="$REPO_ROOT/.claude/agents"
MEMORY_OUT="$REPO_ROOT/.claude/agent-memory"
REPOS_DIR="$REPO_ROOT/repos"

# GCP config for post-creation setup
GCP_PROJECT="scotts-personal"
GCP_WIF_PROVIDER="projects/304054942401/locations/global/workloadIdentityPools/github-actions/providers/github"
GCP_SERVICE_ACCOUNT="github-actions-setup@scotts-personal.iam.gserviceaccount.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()   { echo -e "${BLUE}[info]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*" >&2; }
error() { echo -e "${RED}[error]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }

die() {
    error "$@"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# Parse a YAML config file and return a value by dotted key path
# Usage: yaml_get repos/scottefein--test.yml "sync.agents.enabled"
yaml_get() {
    local file="$1" key="$2"
    python3 -c "
import yaml, sys
with open('$file') as f:
    data = yaml.safe_load(f)
keys = '$key'.split('.')
val = data
for k in keys:
    if val is None:
        val = None
        break
    val = val.get(k) if isinstance(val, dict) else None
if val is None:
    print('')
elif isinstance(val, list):
    print('\n'.join(str(v) for v in val))
elif isinstance(val, bool):
    print(str(val).lower())
else:
    print(val)
"
}

# List all agent names from source
list_agents() {
    for f in "$AGENTS_SRC"/*.md; do
        basename "$f" .md
    done
}

# Compile a single agent: source content + memory template with substitutions
# Usage: compile_agent <agent-name> [output-dir]
compile_agent() {
    local name="$1"
    local out_dir="${2:-$AGENTS_OUT}"
    local src="$AGENTS_SRC/$name.md"
    local template="$TEMPLATE_DIR/agent-memory.md"
    local out="$out_dir/$name.md"

    [[ -f "$src" ]] || die "Agent source not found: $src"
    [[ -f "$template" ]] || die "Template not found: $template"

    # Compile: source content + blank line + template with substitutions
    {
        cat "$src"
        echo ""
        sed "s/{{AGENT_NAME}}/$name/g" "$template"
    } > "$out"
}

# Resolve which agents to include based on repo config
# Usage: resolve_agents <config-file>
# Prints one agent name per line
resolve_agents() {
    local config="$1"
    local enabled include exclude

    enabled="$(yaml_get "$config" "sync.agents.enabled")"
    [[ "$enabled" == "true" ]] || return 0

    include="$(yaml_get "$config" "sync.agents.include")"
    exclude="$(yaml_get "$config" "sync.agents.exclude")"

    local all_agents
    all_agents="$(list_agents)"

    if [[ "$include" == "all" || -z "$include" ]]; then
        # Start with all agents
        local agents="$all_agents"
    else
        # include is a list (one per line from yaml_get)
        local agents="$include"
    fi

    # Apply excludes
    if [[ -n "$exclude" ]]; then
        local filtered=""
        while IFS= read -r agent; do
            if ! echo "$exclude" | grep -qx "$agent"; then
                filtered+="$agent"$'\n'
            fi
        done <<< "$agents"
        agents="$filtered"
    fi

    echo "$agents" | sed '/^$/d'
}

# Create a temporary directory that gets cleaned up on exit
_CLEANUP_DIRS=()
make_temp_dir() {
    local dir
    dir="$(mktemp -d)"
    _CLEANUP_DIRS+=("$dir")
    echo "$dir"
}

cleanup_temp_dirs() {
    local dir
    for dir in "${_CLEANUP_DIRS[@]:-}"; do
        [[ -n "$dir" && -d "$dir" ]] && rm -rf "$dir"
    done
    return 0
}
trap cleanup_temp_dirs EXIT

# Convert owner/repo to config filename
repo_to_config() {
    local slug="$1"
    echo "${slug//\//-\-}.yml"
}

# Convert config filename back to owner/repo
config_to_repo() {
    local filename="$1"
    filename="${filename%.yml}"
    echo "${filename//--//}"
}

# Extract a YAML key path and output as JSON
# Usage: yaml_to_json repos/scottefein--test.yml "setup"
# Outputs the value at that key path as JSON (for pushing to GitHub variables, etc.)
yaml_to_json() {
    local file="$1" key="$2"
    python3 -c "
import yaml, json, sys
with open('$file') as f:
    data = yaml.safe_load(f)
keys = '$key'.split('.')
val = data
for k in keys:
    if val is None or not isinstance(val, dict):
        val = None
        break
    val = val.get(k)
if val is None:
    sys.exit(1)
print(json.dumps(val, separators=(',', ':')))
"
}
