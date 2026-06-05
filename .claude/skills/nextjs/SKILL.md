---
name: nextjs
description: Next.js App Router development patterns, local dev scripts, project structure, and conventions. Auto-load when working with pages, components, layouts, server actions, routing, middleware, or local development workflow.
user-invocable: true
---

# Next.js

## Local Development

### Start / Stop

```bash
bin/dev              # Start dev server on port 3000
bin/dev --port 4000  # Start on a custom port
bin/stop             # Stop the dev server
```

`bin/dev` installs dependencies if `node_modules/` is missing, checks for port conflicts, and saves the PID for clean shutdown. State is kept in `.dev/` (gitignored).

### Environment Variables

Use `.env.local` for local secrets (gitignored). Next.js loads env files in this order:

1. `.env` — shared defaults (committed)
2. `.env.local` — local overrides (gitignored)
3. `.env.development` / `.env.production` — mode-specific

Only variables prefixed with `NEXT_PUBLIC_` are available in client-side code. All others are server-only.

## Project Structure

```
src/
  app/                  # App Router pages and layouts
    layout.tsx          # Root layout (wraps all pages)
    page.tsx            # Home page (/)
    loading.tsx         # Loading UI (automatic Suspense boundary)
    error.tsx           # Error boundary
    not-found.tsx       # 404 page
    globals.css         # Global styles
    api/                # API routes (use sparingly — prefer Server Actions)
      route.ts
    [slug]/             # Dynamic route segments
      page.tsx
  components/           # Shared UI components
  lib/                  # Utilities, API clients, helpers
```

### Key Conventions

- Every route segment is a folder with a `page.tsx`
- `layout.tsx` wraps child routes and persists across navigation
- `loading.tsx` and `error.tsx` are automatic boundaries — add them at any level
- Group routes with `(folder)` syntax — `(auth)/login/page.tsx` doesn't add `/auth` to the URL

## Server Components vs Client Components

**Default: Server Components** — they render on the server, can access databases/APIs directly, and send zero JS to the browser.

Add `"use client"` only when you need:
- `useState`, `useEffect`, or other React hooks
- Browser APIs (`window`, `localStorage`, `IntersectionObserver`)
- Event handlers (`onClick`, `onChange`, etc.)

```typescript
// Server Component (default) — can be async, can fetch data directly
export default async function Page() {
  const data = await db.query('SELECT ...')
  return <div>{data.title}</div>
}
```

```typescript
// Client Component — needed for interactivity
"use client"
import { useState } from "react"

export function Counter() {
  const [count, setCount] = useState(0)
  return <button onClick={() => setCount(count + 1)}>{count}</button>
}
```

**Rule of thumb:** Keep pages and layouts as Server Components. Extract interactive parts into small Client Components.

## Data Fetching

### Server Components (preferred)

Fetch data directly in Server Components — no hooks, no loading states to manage:

```typescript
export default async function Page() {
  const posts = await fetch('https://api.example.com/posts', {
    cache: 'no-store',      // Always fresh
    // next: { revalidate: 60 },  // Or revalidate every 60s
  }).then(r => r.json())

  return <PostList posts={posts} />
}
```

### Server Actions (mutations)

Use Server Actions for form submissions and mutations — not API routes:

```typescript
// In a Server Component or separate file with "use server"
async function createPost(formData: FormData) {
  "use server"
  const title = formData.get("title") as string
  await db.insert({ title })
  revalidatePath("/posts")
}

export default function NewPost() {
  return (
    <form action={createPost}>
      <input name="title" required />
      <button type="submit">Create</button>
    </form>
  )
}
```

For client-side mutation feedback, use `useActionState`:

```typescript
"use client"
import { useActionState } from "react"

export function Form({ action }: { action: (prev: any, formData: FormData) => Promise<any> }) {
  const [state, formAction, pending] = useActionState(action, null)
  return (
    <form action={formAction}>
      <input name="title" required />
      <button disabled={pending}>{pending ? "Saving..." : "Save"}</button>
      {state?.error && <p>{state.error}</p>}
    </form>
  )
}
```

## Styling

Use Tailwind CSS (included in all projects):

```typescript
export default function Card({ title }: { title: string }) {
  return (
    <div className="rounded border border-zinc-800 bg-zinc-900 p-4">
      <h2 className="text-sm font-medium text-zinc-200">{title}</h2>
    </div>
  )
}
```

Global styles go in `src/app/globals.css`:
```css
@import "tailwindcss";
```

## Middleware

`src/middleware.ts` runs before every request — use for auth checks, redirects, headers:

```typescript
import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

export function middleware(request: NextRequest) {
  // Example: redirect unauthenticated users
  if (!request.cookies.get("session")) {
    return NextResponse.redirect(new URL("/login", request.url))
  }
}

export const config = {
  matcher: ["/dashboard/:path*", "/api/:path*"],
}
```

## Key Rules

- Prefer Server Components — only add `"use client"` when you need interactivity
- Prefer Server Actions over API routes for mutations
- Never import server-only code (db clients, secrets) in Client Components
- Use `revalidatePath()` or `revalidateTag()` after mutations to update cached data
- Put shared types in `src/lib/types.ts`, not scattered across components
- Use `loading.tsx` for loading states — don't build custom spinners for every page
- Keep `"use client"` boundaries as small as possible — wrap only the interactive part
- Use dynamic route segments (`[id]`) instead of query parameters when the URL represents a resource
