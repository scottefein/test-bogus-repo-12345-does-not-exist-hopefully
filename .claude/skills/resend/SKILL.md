---
name: resend
description: Resend email patterns, libraries, and configuration for this project. Auto-load when working with sending emails, email templates, transactional email, or the Resend API.
user-invocable: true
---

# Resend

## Library

- **Server-side:** `resend` — the official Node.js SDK

Resend is server-side only. Never import or call it from client components.

## Setup

```typescript
// lib/resend.ts
import { Resend } from 'resend'

export const resend = new Resend(process.env.RESEND_API_KEY)
```

## Sending Email

### Basic send

```typescript
import { resend } from '@/lib/resend'

await resend.emails.send({
  from: `App Name <noreply@${process.env.RESEND_DOMAIN}>`,
  to: 'user@example.com',
  subject: 'Welcome',
  html: '<p>Welcome to the app!</p>',
})
```

### With React Email templates

```typescript
import { resend } from '@/lib/resend'
import WelcomeEmail from '@/emails/welcome'

await resend.emails.send({
  from: `App Name <noreply@${process.env.RESEND_DOMAIN}>`,
  to: 'user@example.com',
  subject: 'Welcome',
  react: WelcomeEmail({ name: 'Scott' }),
})
```

### In a Server Action

```typescript
'use server'
import { resend } from '@/lib/resend'

export async function sendInvite(email: string) {
  const { data, error } = await resend.emails.send({
    from: `Invites <invites@${process.env.RESEND_DOMAIN}>`,
    to: email,
    subject: 'You are invited',
    html: '<p>Click here to join.</p>',
  })

  if (error) throw new Error(`Failed to send: ${error.message}`)
  return data
}
```

## React Email Templates

Use `@react-email/components` for building email templates:

```typescript
// emails/welcome.tsx
import { Html, Head, Body, Container, Text, Button } from '@react-email/components'

interface WelcomeEmailProps {
  name: string
}

export default function WelcomeEmail({ name }: WelcomeEmailProps) {
  return (
    <Html>
      <Head />
      <Body style={{ fontFamily: 'sans-serif' }}>
        <Container>
          <Text>Hi {name},</Text>
          <Text>Welcome to the app!</Text>
          <Button href="https://example.com/dashboard">
            Get Started
          </Button>
        </Container>
      </Body>
    </Html>
  )
}
```

Preview templates locally with: `npx react-email dev`

## Environment Variables

| Variable | Scope | Purpose |
|---|---|---|
| `RESEND_API_KEY` | Server only | Resend API key |
| `RESEND_DOMAIN` | Server only | Sending domain (default: `emails.sefindustries.com`) |

## Configuration

- **Default sending domain:** `emails.sefindustries.com` — shared across all projects
- **From address format:** `Display Name <purpose@${RESEND_DOMAIN}>`
- Common from prefixes: `noreply@`, `invites@`, `notifications@`, `support@`

## Key Rules

- Never import `resend` in client components — it's server-side only
- Always use the `RESEND_DOMAIN` env var for the from address — never hardcode the domain
- Always handle the `error` return from `resend.emails.send()` — don't fire and forget
- Use React Email templates for any email more complex than a single paragraph
- Put email templates in an `emails/` directory at the project root
- Keep email templates simple — many email clients have limited CSS support
