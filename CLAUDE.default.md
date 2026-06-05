# Project

> **Note:** This is a starter CLAUDE.md. As you work in this repo, update this file to reflect the actual architecture, commands, conventions, and decisions specific to this project. A well-maintained CLAUDE.md is the single best way to ensure consistent, high-quality AI assistance across sessions.

## Stack

- **Frontend:** Next.js (App Router), TypeScript, Tailwind CSS
- **Database:** Supabase (Postgres + Auth + Storage)
- **Auth:** Clerk
- **Email:** Resend
- **Hosting:** Vercel
- **AI:** Claude API (Anthropic)

## Commands

```bash
npm run dev          # Start dev server
npm run build        # Production build
npm run lint         # ESLint
npm run test         # Run tests (if configured)
```

## Project Structure

```
src/
  app/               # Next.js App Router pages and layouts
  components/        # React components
  lib/               # Shared utilities, API clients, helpers
  types/             # TypeScript type definitions
public/              # Static assets
supabase/
  migrations/        # Database migrations
```

## Environment Variables

Secrets are managed via GitHub repo secrets (set during repo setup) and Vercel environment variables. For local development, copy `.env.example` to `.env.local`.

Key variables:
- `NEXT_PUBLIC_SUPABASE_URL` — Supabase project URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — Supabase anonymous key
- `SUPABASE_SERVICE_ROLE_KEY` — Supabase service role key (server-side only)
- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` — Clerk publishable key
- `CLERK_SECRET_KEY` — Clerk secret key
- `RESEND_API_KEY` — Resend email API key

## Conventions

- Use server components by default; add `'use client'` only when needed
- Colocate components with the routes that use them when they're single-use
- Use Supabase client from `@supabase/ssr` for server components, `@supabase/auth-helpers-nextjs` for client
- Prefer server actions for mutations over API routes
- Use Zod for runtime validation at system boundaries

## Updating This File

This CLAUDE.md should evolve with the project. Update it when:
- You add a new major dependency or service integration
- You establish a pattern or convention that future work should follow
- You discover a gotcha or non-obvious behavior worth documenting
- The project structure changes significantly
- You make an architectural decision that has lasting implications
