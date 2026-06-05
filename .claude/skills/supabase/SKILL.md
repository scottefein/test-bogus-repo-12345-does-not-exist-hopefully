---
name: supabase
description: Supabase patterns, libraries, and configuration for this project. Auto-load when working with database queries, auth, storage, row-level security, migrations, or any Supabase client code.
user-invocable: true
---

# Supabase

## Libraries

- **Server components / server actions / Route Handlers:** `@supabase/ssr` — use `createServerClient`
- **Client components:** `@supabase/ssr` — use `createBrowserClient`
- **Server-only admin operations:** `@supabase/supabase-js` — use `createClient` with `SUPABASE_SERVICE_ROLE_KEY` (bypasses RLS)

Do NOT use `@supabase/auth-helpers-nextjs` — it is deprecated. Use `@supabase/ssr` for all Next.js integrations.

## Client Setup Pattern

### Server client (for Server Components, Server Actions, Route Handlers)

```typescript
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createSupabaseServer() {
  const cookieStore = await cookies()
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() { return cookieStore.getAll() },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options))
        },
      },
    }
  )
}
```

### Browser client (for Client Components)

```typescript
import { createBrowserClient } from '@supabase/ssr'

export function createSupabaseBrowser() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
```

### Admin client (for server-only operations that bypass RLS)

```typescript
import { createClient } from '@supabase/supabase-js'

export function createSupabaseAdmin() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  )
}
```

## Middleware (auth session refresh)

Supabase auth requires middleware to refresh the session on every request:

```typescript
// middleware.ts
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request })
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() { return request.cookies.getAll() },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            request.cookies.set(name, value)
            response.cookies.set(name, value, options)
          })
        },
      },
    }
  )
  await supabase.auth.getUser()
  return response
}
```

## Migrations

- Migration files live in `supabase/migrations/`
- Use `npx supabase migration new <name>` to create a new migration
- Always write RLS policies for new tables
- Use `npx supabase db push` to apply migrations to remote
- Use `npx supabase gen types typescript --project-id <ref> > src/types/database.ts` to regenerate types after schema changes

## Row-Level Security

Every table must have RLS enabled. Common patterns:

```sql
-- Enable RLS
alter table public.my_table enable row level security;

-- Users can only read their own rows
create policy "Users read own data" on public.my_table
  for select using (auth.uid() = user_id);

-- Users can insert their own rows
create policy "Users insert own data" on public.my_table
  for insert with check (auth.uid() = user_id);
```

## Environment Variables

| Variable | Scope | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Public | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Public | Anonymous/public key (safe for browser, respects RLS) |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only | Admin key (bypasses RLS — never expose to client) |

## Key Rules

- Never expose `SUPABASE_SERVICE_ROLE_KEY` to client code or `NEXT_PUBLIC_` env vars
- Always use the server client in Server Components — never create a browser client on the server
- Always write RLS policies when creating tables — no exceptions
- Use Supabase Auth (not Clerk) for database-level auth unless the project explicitly uses Clerk
- Prefer `.select()` with specific columns over `select('*')` for performance
- Use database functions and RPC calls for complex operations rather than multiple round trips
