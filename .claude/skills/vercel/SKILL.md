---
name: vercel
description: Vercel deployment patterns, configuration, and Next.js hosting conventions for this project. Auto-load when working with deployment config, environment variables, serverless functions, edge runtime, or Vercel-specific features.
user-invocable: true
---

# Vercel

## Deployment

- **Framework:** Next.js (App Router)
- **Build command:** `npm run build`
- **Output directory:** `.next`
- **Node.js version:** 20.x
- Every push to `master`/`main` triggers a production deployment
- Every push to a PR branch triggers a preview deployment

## Environment Variables

Environment variables are set at the Vercel project level across three targets:

| Target | When used |
|---|---|
| `production` | Production deployments (main branch) |
| `preview` | Preview deployments (PR branches) |
| `development` | `vercel dev` local development |

Variables are managed via the setup plugin and should not be set manually unless overriding for a specific environment.

For local development, use `.env.local` (gitignored) — not Vercel env vars.

## vercel.json

Only create `vercel.json` when you need to override defaults. Common uses:

```json
{
  "framework": "nextjs",
  "headers": [
    {
      "source": "/api/(.*)",
      "headers": [
        { "key": "Access-Control-Allow-Origin", "value": "*" }
      ]
    }
  ],
  "redirects": [
    { "source": "/old-path", "destination": "/new-path", "permanent": true }
  ]
}
```

Do NOT add `vercel.json` just for build settings — those are configured in the Vercel project.

## Serverless Functions

Next.js API routes and Server Actions automatically deploy as serverless functions.

### Timeouts and limits

| Plan | Serverless timeout | Edge timeout | Body size |
|---|---|---|---|
| Hobby | 10s | 30s | 4.5 MB |
| Pro | 60s | 30s | 4.5 MB |

For long-running operations, use background functions or queue-based patterns.

### Edge Runtime

Use edge runtime for latency-sensitive routes:

```typescript
export const runtime = 'edge'

export async function GET() {
  // Runs at the edge, close to the user
}
```

Constraints: no Node.js APIs (fs, child_process), limited npm package support.

## Cron Jobs

Define cron jobs in `vercel.json`:

```json
{
  "crons": [
    {
      "path": "/api/cron/daily-digest",
      "schedule": "0 17 * * *"
    }
  ]
}
```

- Cron routes must verify the `CRON_SECRET` header in production
- Maximum frequency: once per minute (Pro), once per day (Hobby)

```typescript
export async function GET(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response('Unauthorized', { status: 401 })
  }
  // ... cron logic
}
```

## Preview Deployments and PR Workflow

- Each PR gets a unique preview URL
- Preview deployments use `preview` environment variables
- Use Vercel's comment bot to see deployment status on PRs

## Key Rules

- Never commit `.vercel/` directory — it's local state
- Never hardcode deployment URLs — use `VERCEL_URL` or `NEXT_PUBLIC_VERCEL_URL` env vars for dynamic URLs
- Prefer Server Actions over API routes for form submissions and mutations
- Keep serverless functions fast — offload heavy work to queues or background jobs
- Use `edge` runtime only when you specifically need low latency and don't need Node.js APIs
- Don't add `vercel.json` unless you need it — Next.js conventions handle most cases
