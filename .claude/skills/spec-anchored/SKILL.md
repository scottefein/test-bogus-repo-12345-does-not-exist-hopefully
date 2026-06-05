---
name: spec-anchored
description: The spec-anchored development pipeline — how agents read the versioned /spec source of truth, compute blast radius from trace-map.yaml, propose a spec delta, implement against the approved spec on a feature branch, and verify conformance. Auto-load when working a spec-anchored-change workflow (the spec-pm, coding, or conformance-verifier steps), when a GitHub issue is labeled spec-change, or when touching /spec, trace-map.yaml, or the spec-anchored pipeline migration/agents.
user-invocable: false
---

# Spec-Anchored Development

The app's design is captured in a versioned **`/spec`** directory that is canonical in
git. Change requests arrive as GitHub issues; a spec delta is proposed and approved
*before* code; the code is then made to match the approved spec on a feature branch,
verified for conformance (no regressions across the blast radius), proven with captured
evidence, and merged. Read `spec/constitution.md` first — it is the always-loaded
grounding. **Where the spec and the code disagree, the spec is the intent.**

## The `/spec` layout (everything is addressable by stable ID)

```
spec/
  constitution.md          # durable principles — read this every time
  decisions/ADR-NNNN-*.md   # one architectural decision per file (the "why")
  stories/US-NNNN-*.md      # As-a / I-want / so-that + Given/When/Then
  requirements/FR.md        # FR-001, FR-002, … functional requirements
  requirements/NFR.md       # NFR-001, … non-functional requirements
  trace-map.yaml            # REQ-id ↔ story ↔ code path(s) ↔ conformance check(s)
  VERSION                   # bump on each approved change
```

**Load selectively.** Read `constitution.md` always. Then load only the FR/NFR/US/ADR
entries in the **blast radius** of the change — never dump the whole tree into context.

## Blast radius (the load-bearing move)

`trace-map.yaml` is the index that makes "what must change" and "what must stay green"
answerable instead of guessed. For a change:

1. Identify the requirement IDs it touches (existing FR/NFR, or new ones you'll add).
2. For each, read its `trace-map.yaml` entry → the **`code`** paths (what to change) and
   **`checks`** (what must stay green) and **`adrs`** (decisions that constrain you).
3. The union of all touched entries' `code` + `checks` is the **blast-radius set**. The
   conformance gate must stay green across *that whole set*, not just the new lines —
   this is the "no loss of functionality" guarantee.

If the trace map is missing or stale for the area you touch, **fixing it is part of the
job** (constitution P-3 / NFR-004). An inaccurate trace map makes every downstream
"no regression" claim a guess.

---

## Your role depends on your workflow step

### If you are the **spec-pm / reconcile** agent (step 0)

Input: a GitHub issue (number/body/repo in your run input). Output: a **spec-only draft
PR** on a new feature branch.

1. **Understand the request** from the issue. If it's natural-language, restate it as a
   concrete change to the spec.
2. **Reconcile against `/spec`.** Determine how it fits: which FR/NFR/US/ADR it adds,
   edits, or contradicts. Compute the blast radius from `trace-map.yaml`.
3. **Write the spec delta** — edit only `/spec` files: add/modify the FR/NFR with new
   stable IDs (append; never renumber), add a US with Given/When/Then, add an ADR if the
   request implies a real decision, and **update `trace-map.yaml`** to point the new
   REQ-ids at the code paths you expect to change and the checks that should prove them.
   Bump `spec/VERSION`.
4. **Conflict report.** If the request contradicts an existing ADR or requirement, say so
   explicitly — that's a signal for the human to resolve at the cheapest moment.
5. **Open a spec-only draft PR** — commit **only `/spec`** changes on a new feature
   branch, push, and open a *draft* PR targeting the repo's default branch. Recipes:

   ```bash
   # branch off the repo default (develop here)
   git config user.name scottefein && git config user.email feinberg.scott@gmail.com
   git checkout -b spec/<issue-number>-<slug>
   git add spec/ && git commit -m "spec: <summary> (closes #<issue>)"
   git push "https://x-access-token:${SEF_MANAGER_GITHUB_PAT}@github.com/<owner>/<repo>.git" HEAD
   # open as DRAFT (REST):
   curl -sS -X POST -H "Authorization: Bearer $SEF_MANAGER_GITHUB_PAT" \
     -H "Accept: application/vnd.github+json" \
     https://api.github.com/repos/<owner>/<repo>/pulls \
     -d '{"title":"spec: <summary>","head":"spec/<...>","base":"develop","draft":true,"body":"Closes #<issue>\n\n<conflict report + blast radius>"}'
   # (gh pr create --draft also works if gh is on PATH)
   ```
6. **Hand off.** Call `workflow_handoff` with `summary` = the conflict report + the
   blast-radius set (markdown), `fields` = `{"branch": "...", "req_ids": "FR-0xx,...",
   "issue": "#<n>"}`, and `pr_url` = the draft PR URL. The next step is the
   **spec-approval gate** — your summary is what the human sees. **This approval is
   spec-approved, not merge-approved:** it only unblocks coding.

### If you are the **coding** agent (step 2, after spec approval)

You receive the approved PR (branch + spec diff + issue) in your prior-handoff context.

1. **Check out the branch** the PM created (in `fields.branch` / the PR head). Work on the
   **same branch** so the PR fills out to spec + code as one reviewable unit.
2. **Implement the approved spec delta** — make the code satisfy the new/changed
   requirements. Touch the `code` paths the trace map names for the blast-radius set.
3. **Keep the trace map in sync** — if the real code paths differ from what the PM
   guessed, fix `trace-map.yaml` so each touched REQ-id points at the actual files +
   checks. This is part of done.
4. **Run the blast-radius checks** locally and make them green: the `checks` for every
   touched REQ-id (tests, lint, typecheck). Show the output — the conformance gate reads
   your transcript.
5. **Push commits** to the same branch (PAT recipe above; never `git push -u`). Do **not**
   merge — and don't un-draft the PR yourself either. When your coding step *completes*,
   the engine transitions the PR from draft → ready-for-review automatically (FR-009: the
   `mark_pr_ready` flag on the coding step drives `advance_run` to call the GitHub
   un-draft). The actual merge to `develop` is a **dedicated engine `merge` step** (FR-010)
   that runs only *after* the implementation-approval gate — never the agent, never the
   approval side-effect. So your job ends at "spec + code pushed, checks green, handed off".
6. **Hand off** with `summary` = what you implemented + which checks you ran and their
   results, `fields` = `{"verdict":"ready-for-conformance"}`, `pr_url` = the PR (pass it so
   `runs.pr_url` is set — the engine merge step merges exactly that PR).

### If you are the **conformance-verifier** agent (step 3)

Independent verification + intent review + evidence. You sit between coding and the
implementation-approval gate.

1. **Deterministic layer** — check out the branch and **re-run** the blast-radius checks
   from `trace-map.yaml` (regression suite across the whole set, lint, typecheck). Report
   each command + result in your handoff (a boolean eval check reads your transcript and
   will resurrect you if the evidence is thin).
2. **Intent review** — read the **spec delta vs the code diff**. Does the implementation
   satisfy the intent? Does it quietly violate an existing ADR? Is a changed requirement
   left unimplemented? Flag discrepancies in your summary.
3. **If deficient → hand back to coding.** Call `workflow_handoff` with
   `target_step_index` = the coding step's index and a *specific* remediation (files,
   behaviors, failing checks — not "make it better"). Bounded by the revisit cap.
4. **If conformant → capture evidence.** For a user-visible change, record a short video +
   screenshot of it working from the branch's **Vercel preview** (preferred) using the
   **`demo-recording`** skill (`scripts/record-demo.mjs --base <preview-url> --upload`).
   Point `--base` at the PR's Vercel preview; use the Vercel-protection + Clerk bypass
   recipe in CLAUDE.md ("Live debugging deployed previews"). If the preview isn't
   reachable, fall back to local `/run-app`. Backend-only changes may skip the video.
5. **Hand off with the evidence attached.** Pass the uploaded objects from
   `.demo-out/uploads.json` as `workflow_handoff` **`attachments`** (the same shape
   `newsfeed_send` takes: `{key, url, name, content_type, size}`), plus `summary` = the
   conformance verdict (checks run + results, intent-review findings) and `pr_url`. The
   platform renders those attachments inline on the **implementation-approval** card so
   the human approves a result they can see. Approval of that gate resumes the run onto the
   dedicated engine `merge` step, which merges the PR to `develop` (the agent never merges).

## Conventions

- **Spec IDs are append-only and stable.** Never renumber FR/NFR/US/ADR — other entries
  and the trace map reference them.
- **The first PR is spec-only** (only `/spec` changed); code commits land on the *same*
  branch after spec approval.
- **Spec-approved ≠ merge-approved.** Never merge at the first gate. The merge happens
  only after the implementation-approval gate.
- **Trace-map accuracy is definition-of-done** for every change.
- **Reuse the engine** (constitution P-4): express behavior as workflow steps, agents,
  eval checks, and this skill — not new orchestration code.
