# AlphaPos Email Confirmation — Design & Locale Decision

**Date:** 2026-07-25  
**Status:** Approved  
**Template:** `supabase/templates/confirmation.html`

---

## 1. Visual direction (international standard)

Ship a **light transactional** layout — not a full dark email.

| Element | Choice | Rationale |
|---|---|---|
| Outer canvas | `#F4F6F9` | Neutral SaaS chrome (Gmail/Outlook safe) |
| Card | White + `#E2E8F0` border | Clear focus, high trust for verify/auth mail |
| Headline / body | `#0F172A` / `#475569` | Strong readability |
| CTA | Solid `#2D71F8` button | Primary action, not a plain text link |
| OTP | Large mono in soft gray panel | Secondary path, scannable |
| Footer | Muted slate + plain URL | Deliverability + accessibility |

This matches common patterns from Stripe / Linear / Notion / Square-style auth mail: brand → one headline → one button → code → fallback link → ignore line.

**Dark full-bleed** was evaluated and rejected as the default (client forcing, trust, spam heuristics). Brand accent blue is enough for AlphaPos identity.

---

## 2. Where should language selection live?

### Verdict

| Screen | Language control? | Why |
|---|---|---|
| **Signup (account step)** | **Required** | Confirmation email is sent at signup — locale must already be chosen |
| **Login** | **Recommended** (same auth chrome) | Same `MerchantAuthView`; also covers recovery / resend flows |
| **Settings (after enter app)** | Keep | Updates UI + **future** emails only — too late for first confirm mail |
| First-launch mode only | Not enough | User may skip; mode ≠ locale |

**Product rule:** Locale for transactional email = language selected **before** `signUp` / resend confirmation.  
Do **not** rely on Settings alone.

### Why signup matters more than login

```
Signup → GoTrue sends confirmation email  ← language must be known HERE
Login  → only after email already confirmed
Settings → user already inside the app
```

If the picker exists only after login/Settings:

1. First confirm email is always English (or server default)  
2. User cannot match Thai/other UI to the email they just received  
3. Support load increases (“อีเมลเป็นภาษาอังกฤษ”)

### Recommended UX

1. Compact language control on **auth screens** (login + signup share one chrome) — top-right or under brand.  
2. Default: device locale if supported, else `en`.  
3. On `signUp`, write `user_metadata.preferred_language` (or `locale`) = `app_language`.  
4. Server/mailer selects template (or copy block) from that metadata.  
5. Changing language in Settings updates metadata for later mail (recovery, receipts, billing).

### Technical note (GoTrue)

Stock GoTrue uses **one** confirmation HTML template. Multi-language options:

| Approach | Effort | Notes |
|---|---|---|
| A. One template, English-only | Low | Current ship path |
| B. Auth hook / custom mailer by `preferred_language` | Medium | Best long-term |
| C. Multiple `GOTRUE_MAILER_TEMPLATES_*` via fork/proxy | High | Unusual on self-hosted |

Until B exists, UI language on signup still matters for in-app copy; email stays EN until localized templates are wired.

---

## 3. Content blocks (must have)

1. AlphaPos wordmark  
2. Headline: Confirm your email  
3. One supporting sentence (+ email if available)  
4. Primary button → `{{ .ConfirmationURL }}`  
5. OTP `{{ .Token }}` + expiry hint  
6. Plain URL fallback  
7. “If you didn’t sign up…”  
8. Sender footer: no-reply@alphaposweb.com  

---

## 4. Wiring

```toml
[auth.email.template.confirmation]
subject = "Confirm your email — AlphaPos"
content_path = "./supabase/templates/confirmation.html"
```

VPS: copy template → point `GOTRUE_MAILER_TEMPLATES_CONFIRMATION` → restart `supabase_auth_AlphaPos`.

---

## 5. Shipped (2026-07-25 / 2026-07-26)

1. Light multi-locale HTML: `confirmation.html` + `recovery.html`  
2. Public URLs:  
   - `https://alphaposweb.com/email/confirmation.html`  
   - `https://alphaposweb.com/email/recovery.html`  
3. GoTrue templates wired for confirmation + recovery  
4. Auth UI language control on `MerchantAuthView`  
5. Signup + forgot-password stamp `preferred_language` (via `set-auth-locale`)  
6. Deploy helper: `scripts/deploy-auth-emails.sh`  
