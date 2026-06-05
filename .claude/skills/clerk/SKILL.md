---
name: clerk
description: Clerk auth patterns, libraries, and configuration for this project. Auto-load when working with authentication, user management, sign-in/sign-up flows, protecting routes, or Clerk components.
user-invocable: true
---

# Clerk

## Libraries

- **React components:** `@clerk/nextjs` — provides `<SignIn>`, `<SignUp>`, `<UserButton>`, etc.
- **Server-side auth:** `@clerk/nextjs/server` — provides `auth()`, `currentUser()`
- **Middleware:** `@clerk/nextjs/server` — provides `clerkMiddleware`, `createRouteMatcher`

## Middleware Setup

```typescript
// middleware.ts
import { clerkMiddleware, createRouteMatcher } from '@clerk/nextjs/server'

const isPublicRoute = createRouteMatcher([
  '/',
  '/sign-in(.*)',
  '/sign-up(.*)',
  '/api/webhooks(.*)',
])

export default clerkMiddleware(async (auth, request) => {
  if (!isPublicRoute(request)) {
    await auth.protect()
  }
})

export const config = {
  matcher: [
    '/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)',
    '/(api|trpc)(.*)',
  ],
}
```

## Server-Side Auth

### In Server Components

```typescript
import { auth, currentUser } from '@clerk/nextjs/server'

export default async function Page() {
  const { userId } = await auth()
  if (!userId) redirect('/sign-in')

  const user = await currentUser()
  return <p>Hello {user?.firstName}</p>
}
```

### In Server Actions

```typescript
'use server'
import { auth } from '@clerk/nextjs/server'

export async function myAction() {
  const { userId } = await auth()
  if (!userId) throw new Error('Unauthorized')
  // ...
}
```

### In Route Handlers

```typescript
import { auth } from '@clerk/nextjs/server'

export async function GET() {
  const { userId } = await auth()
  if (!userId) return new Response('Unauthorized', { status: 401 })
  // ...
}
```

## Client Components

```typescript
'use client'
import { useUser, useAuth } from '@clerk/nextjs'

export function MyComponent() {
  const { user, isLoaded } = useUser()
  const { userId, getToken } = useAuth()
  // ...
}
```

## Layout Setup

```typescript
// app/layout.tsx
import { ClerkProvider } from '@clerk/nextjs'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <ClerkProvider>
      <html lang="en">
        <body>{children}</body>
      </html>
    </ClerkProvider>
  )
}
```

## Auth Pages

Place auth pages at these conventional paths:

```
app/sign-in/[[...sign-in]]/page.tsx
app/sign-up/[[...sign-up]]/page.tsx
```

```typescript
import { SignIn } from '@clerk/nextjs'

export default function SignInPage() {
  return <SignIn />
}
```

## Environment Variables

| Variable | Scope | Purpose |
|---|---|---|
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Public | Clerk publishable key (safe for browser) |
| `CLERK_SECRET_KEY` | Server only | Clerk secret key |
| `NEXT_PUBLIC_CLERK_SIGN_IN_URL` | Public | Sign-in page path (default: `/sign-in`) |
| `NEXT_PUBLIC_CLERK_SIGN_UP_URL` | Public | Sign-up page path (default: `/sign-up`) |

## Connecting Clerk to Supabase

When using Clerk as the auth provider with Supabase as the database, use Clerk's JWT template to generate Supabase-compatible tokens:

1. In Clerk Dashboard: create a JWT template for Supabase
2. In code: use `getToken({ template: 'supabase' })` to get a token
3. Pass the token to the Supabase client

```typescript
import { auth } from '@clerk/nextjs/server'
import { createClient } from '@supabase/supabase-js'

export async function createClerkSupabaseClient() {
  const { getToken } = await auth()
  const token = await getToken({ template: 'supabase' })

  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { global: { headers: { Authorization: `Bearer ${token}` } } }
  )
}
```

## Key Rules

- Always protect API routes and Server Actions with `auth()` — never trust client-side auth alone
- Use `clerkMiddleware` — not the deprecated `authMiddleware`
- Use `auth()` (async) not `auth` (sync) — the sync version is deprecated
- Never expose `CLERK_SECRET_KEY` to client code
- Use Clerk's built-in components (`<SignIn>`, `<UserButton>`) rather than building custom auth UI unless there's a specific design requirement
- For webhook verification, use `svix` to verify Clerk webhook signatures
