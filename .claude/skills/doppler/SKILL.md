---
name: doppler
description: Doppler secret management patterns for this project. Auto-load when working with environment variables, secrets, .env files, or anything in deploy.yml's secrets/env_vars blocks. Covers where secrets live (Doppler is source of truth), how they sync to GitHub Actions / Vercel / GCP Secret Manager, the single-secret JSON pattern Cloud Run uses, naming conventions, and CLI/API workflows.
user-invocable: true
---

# Doppler

Doppler is the source of truth for all secrets in this project. The Doppler dashboard pushes values to three destinations; **never edit secrets directly in those destinations** — they get overwritten on the next sync.

## Project Layout

- **Project:** `sef-industries-manager-repo`
- **Configs (environments):**
  - `dev` — Vercel preview branches
  - `stg` — staging (currently empty)
  - `prd` — Vercel production
  - `prd_google-cloud-run` — service-specific config that syncs to Cloud Run via GCP Secret Manager
  - `dev_personal` — local overrides

A given secret often lives in multiple configs (e.g. `NOTION_API_KEY` in both `prd` and `prd_google-cloud-run`) because it's needed by both the frontend and backend.

## Sync Destinations

| Destination | Source config | Strategy | What it produces |
|---|---|---|---|
| **GitHub Actions** (`scottefein/sef-industries-manager`) | `prd_google-cloud-run` | One repo secret per Doppler key | `${{ secrets.SEF_MANAGER_API_SECRET }}` etc. usable in workflows |
| **Vercel** (Production) | `prd` | One env var per Doppler key | Available as `process.env.<KEY>` in Next.js |
| **Vercel** (Preview) | `dev` | One env var per Doppler key | Available in PR preview deployments |
| **GCP Secret Manager** (`scotts-personal`) | `prd_google-cloud-run` | **Single-secret JSON** | One secret `sef-industries-manager-doppler-secret` containing all keys as JSON |

The `single-secret` strategy on the GCP sync is important: Cloud Run mounts that one secret as a file and unpacks it at startup. See "Cloud Run Loader" below.

## Cloud Run Loader

Because GCP uses the single-secret strategy, Cloud Run can't bind individual env vars from individual GCP secrets. Instead:

1. `deploy.yml` mounts the JSON blob as a file:
   ```yaml
   secrets_update_strategy: overwrite
   secrets: |
     /etc/doppler/secrets.json=sef-industries-manager-doppler-secret:latest
   ```
2. `doppler_loader.py` (imported at the top of `main.py`, before any router) reads `/etc/doppler/secrets.json` and populates `os.environ`:
   ```python
   import doppler_loader  # noqa: F401  -- must import before anything reads env
   ```
3. Application code reads env vars normally: `os.environ.get("SEF_MANAGER_API_SECRET")`.

`secrets_update_strategy: overwrite` is critical — without it, the deploy action defaults to `merge`, which leaves stale individual secret bindings on the service.

## Naming Conventions

- **All secret keys are `UPPER_SNAKE_CASE`** in Doppler. The sync mirrors this verbatim to every destination.
- For service-scoped secrets, prefix with the service name: `SEF_MANAGER_API_SECRET`, `SEF_MANAGER_GITHUB_PAT`. This makes the source app obvious in any destination's secret list.
- Application code reads the Doppler key directly — **no aliasing**. The loader was simplified to no longer remap `SEF_MANAGER_API_SECRET → API_SECRET`; rename the code instead.
- The `DOPPLER_*` keys (`DOPPLER_PROJECT`, `DOPPLER_CONFIG`, `DOPPLER_ENVIRONMENT`) are auto-injected by Doppler — `doppler_loader.py` skips them when populating `os.environ`.

## CLI Quick Reference

```bash
# Where am I scoped?
doppler configure

# List secret names in the current scope
doppler secrets --only-names
doppler secrets --only-names --config prd_google-cloud-run

# Set a secret
doppler secrets set KEY="value" --config prd_google-cloud-run --no-interactive

# Get a value
doppler secrets get KEY --plain --config prd

# Delete
doppler secrets delete KEY --config prd
```

The CLI does **not** have `integrations` or `syncs` subcommands — those are dashboard-only. Use the API for read-only inspection (see below).

## API Inspection

```bash
DOPPLER_TOKEN=$(doppler configure get token --plain)

# List all integrations and their syncs (status, last sync time)
curl -s -H "Authorization: Bearer $DOPPLER_TOKEN" \
  "https://api.doppler.com/v3/integrations" | python3 -m json.tool

# List secret names in a config
curl -s -H "Authorization: Bearer $DOPPLER_TOKEN" \
  "https://api.doppler.com/v3/configs/config/secrets/names?project=sef-industries-manager-repo&config=prd_google-cloud-run" \
  | python3 -m json.tool
```

Use this to confirm a sync ran (`lastSyncedAt`, `status: "synced"`) before chasing a "secret missing" bug.

## Verification Checklist

After changing secrets in Doppler:

1. **GitHub Actions:** `gh secret list -R scottefein/sef-industries-manager` — timestamps on all Doppler-managed secrets should be within seconds of each other (sync runs on every Doppler write).
2. **Vercel:** Trigger a redeploy if you need the new value; preview/production envs are picked up at build time, not runtime.
3. **Cloud Run:** The single-secret JSON updates immediately. Verify with:
   ```bash
   gcloud secrets versions access latest \
     --secret=sef-industries-manager-doppler-secret \
     --project=scotts-personal | jq 'keys'
   ```
   Cloud Run picks up the new version on the **next deploy** (the `:latest` binding is resolved at deploy time, not per-request). Re-deploy to pick up rotated secrets.

## Adding a New Secret

1. `doppler secrets set KEY="value" --config prd_google-cloud-run --no-interactive` (and/or `--config prd` if frontend needs it).
2. Sync runs automatically; verify in GCP/GitHub/Vercel as above.
3. For Cloud Run: redeploy. Push to `develop` triggers staging redeploy via `deploy-staging`; push to `master` triggers prod via `deploy-prod` (see `deploy.yml`).
4. For Vercel: redeploy.
5. For GitHub Actions: available immediately as `${{ secrets.KEY }}`.

## Gotchas

- **Sync is one-way (Doppler → destination).** Editing a value in GitHub Actions / Vercel / GCP gets overwritten.
- **Cloud Run picks up new values on deploy, not on Doppler write.** The `:latest` GCP secret binding is resolved at deploy time. Rotate → redeploy.
- **`secrets_update_strategy` defaults to `merge`** in the `deploy-cloudrun` action. With our single-secret pattern, you want `overwrite` so stale per-key bindings on the service get cleared.
- **Don't run `pip install --user`** in this repo — use the venv at `.venv/`. Same applies for the Doppler CLI itself: install at the user level (`brew install dopplerhq/cli/doppler` or the standalone install script), not inside a venv.
- **Local dev uses `.env.local`**, not `doppler run --`. The `.env.local` file is gitignored and contains the same keys; Doppler is for deployed environments.
- **Don't add a Doppler key whose value is a multiline JSON string** unless you've confirmed the destination handles it. GCP and GitHub Actions both do; Vercel may not.
