---
name: demo-recording
description: Record a short video + screenshots of a feature you just built and post them to the Newsfeed for Scott to review. Use after shipping a user-visible change when you want to *show* the feature working (not just describe it) — boot the app, drive it as a user would, capture a demo clip + screenshots, upload them, and attach them to a newsfeed_send message. Triggers — "record a demo", "show me the feature", "send a video", "screenshot the change to the newsfeed".
---

# Demo recording → Newsfeed

Turn a finished, user-visible feature into a short **demo video + screenshots**
posted to the Newsfeed, so Scott can see it working without checking out the
branch. The pieces:

1. **Boot** the app the user actually uses.
2. **Drive** it as a signed-in user (navigate, click, fill, etc.).
3. **Capture** a `.webm` video + labelled screenshots.
4. **Upload** them to the private `newsfeed-attachments` bucket → signed URLs.
5. **Post** a `newsfeed_send` message with those URLs as `attachments`.

You only need this for changes a human can *look at*. A backend-only / refactor
change doesn't need a demo — a normal newsfeed update is fine.

---

## In the `sef-industries-manager` repo (the fast path)

This repo ships everything: a bootable stack, a Clerk test user, and a recorder
that does capture **and** upload in one shot.

### 0. One-time prep (fresh sandbox)

A fresh agent sandbox has the repo cloned but not the local-dev tooling
installed. Run the idempotent bootstrap once — it installs Node deps
(`record-demo.mjs` needs `@playwright/test` + `@clerk/testing`), the Python
backend deps, and provisions the Clerk test user into `.env.test.local`:

```bash
scripts/setup-local-dev.sh
```

(Chromium itself is pre-baked into the Modal image; `jq`/`lsof` — which the boot
script needs — are baked in too.)

### 1. Boot the app

```bash
doppler run --project sef-industries-manager-repo --config dev -- \
  scripts/local-dev-preview.sh
```

Brings up FastAPI on `:8080` + Next.js on `:3000` against the persistent
`local-dev` Supabase branch. See the **`run-app`** / **`local-dev`** skills for
the full story (Clerk-bypass, branch, gotchas, `/cleanup` when done).

### 2. Write a steps file

A JSON array of actions, run in order. One key per step:

| key | meaning |
| --- | --- |
| `goto` | path or URL to navigate to |
| `click` | Playwright selector to click |
| `fill` | `[selector, value]` |
| `press` | key to press (e.g. `"Enter"`) |
| `waitFor` | selector to wait for |
| `wait` | milliseconds to pause |
| `scroll` | pixels to scroll down |
| `screenshot` | label → a captured frame (`.demo-out/NN-<label>.png`) |

```jsonc
// demo-steps.json — demo the feature from issue #NNN
[
  { "goto": "/orchestra/projects" },
  { "screenshot": "projects-list" },
  { "click": "text=New project" },
  { "fill": ["#name", "Demo Co"] },
  { "press": "Enter" },
  { "waitFor": "text=Demo Co" },
  { "screenshot": "created" }
]
```

Keep it short — aim for a ~15–40s clip that lands the "before → action →
result" beat for the one feature you shipped.

### 3. Record + upload

```bash
doppler run --project sef-industries-manager-repo --config dev -- \
  node scripts/record-demo.mjs --steps demo-steps.json --title "Feature X" --upload
```

This signs in as the Clerk test user (reusing `browse.mjs`'s cached session),
runs the walkthrough recording a `.webm`, screenshots each labelled step, then
uploads the video + screenshots to the `newsfeed-attachments` bucket. It prints
the public URLs as JSON (also saved to `.demo-out/uploads.json`):

```json
[
  { "url": "https://…/demo.webm", "name": "demo.webm", "content_type": "video/webm", "size": 1048576 },
  { "url": "https://…/01-projects-list.png", "name": "01-projects-list.png", "content_type": "image/png", "size": 84211 }
]
```

Drop `--upload` to only capture locally (files land in `.demo-out/`); useful
for iterating on the steps before posting.

Targeting a deployed preview instead of localhost? Add
`--base https://manager-stg.sefindustries.com` (needs
`VERCEL_AUTOMATION_BYPASS_SECRET` — see the staging-preview section of
`CLAUDE.md`).

### 4. Post to the Newsfeed

Call the `newsfeed_send` MCP tool, passing the uploaded objects straight
through as `attachments` (the array shape matches exactly):

```
newsfeed_send(
  project_id = "<the project UUID>",
  priority   = "P1",
  content    = "📹 **Feature X** is live on `feature/x`.\n\nShort clip + screenshots of the new flow. PR: #NNN",
  attachments = [ …the objects from uploads.json… ],
)
```

The video and images render inline in the Newsfeed UI. Use `P1` (normal) for a
routine demo; `P0` only if you genuinely need Scott's eyes now.

---

## In other managed repos (the portable path)

`record-demo.mjs` and the Clerk-test-user wiring are specific to this repo.
Elsewhere, the **upload + newsfeed** half still works the same — what changes is
how you boot and drive the app.

1. **Boot** the app however that repo documents it (check its `CLAUDE.md` /
   `README` / its own skills). Modal sandboxes have Node 20 + Playwright
   Chromium pre-baked at `$PLAYWRIGHT_BROWSERS_PATH`, so headless browser
   driving works out of the box.
2. **Capture** with a short Playwright script: open a context with
   `recordVideo: { dir }`, walk the page, `page.screenshot(...)` at key
   moments, then `context.close()` and read `await page.video().path()`.
   (Crib the structure from `scripts/record-demo.mjs`.)
3. **Upload** each file to the private bucket via the manager backend — this is
   the cross-repo primitive, available from any sandbox (they all carry
   `API_URL` + `SEF_MANAGER_API_SECRET`):

   ```bash
   curl -sf -X POST "$API_URL/api/newsfeed/attachments" \
     -H "Authorization: Bearer $SEF_MANAGER_API_SECRET" \
     -F "file=@.demo-out/demo.webm;type=video/webm"
   # → {"url":"https://…/demo.webm","name":"demo.webm","content_type":"video/webm","size":…}
   ```

   Repeat per screenshot; collect the returned objects.
4. **Post** with `newsfeed_send`, passing those objects as `attachments` — same
   as step 4 above.

---

## Notes & limits

- **Size cap: 25 MiB per file** (the bucket's `file_size_limit`). Keep clips
  short; a ~30s headless `.webm` is typically a few MB. Oversize uploads get a
  `413` — trim the walkthrough or drop the resolution (`--width/--height`).
- **Private bucket + signed URLs.** The bucket is private; uploads return a
  durable `key` plus a short-lived **signed** `url`, and the backend re-signs
  the key per view so only the authenticated viewer rendering the inbox gets a
  working link. Pass the whole uploaded object (incl. `key`) to `newsfeed_send`
  — don't persist a public URL. Still drive the **test** user against
  **dev/staging** data; signed URLs are bearer tokens until they expire.
- **The video is the whole session**, including sign-in. If you don't want the
  sign-in flicker in frame, the cached session (`.playwright-state.json` from a
  prior `browse.mjs`/`record-demo.mjs` run) skips it — the recording starts on
  your first `goto`.
- **A failed step still produces output**: `record-demo.mjs` screenshots the
  error state and exits non-zero, so you can see where the walkthrough broke.
- **Clean up** the local stack with `/cleanup` when you're done (this repo).

## Related

- **`run-app`** / **`local-dev`** — boot + drive the stack as the Clerk test user.
- **`scripts/browse.mjs`** — single-page screenshot driver this recorder is built on.
- **`newsfeed_send`** MCP tool — `attachments` is `[{url, name?, content_type?, size?}]`.
- Backend: `POST /api/newsfeed/attachments` in `routers/newsfeed.py`.
