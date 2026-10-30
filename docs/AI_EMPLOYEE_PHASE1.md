# M365Buddy AI Employee — Phase 1 staging

## Scope
Approval-first intake and review only. Phase 1 does not publish content to the site, GitHub Discussions, or any external destination.

## Staging resources
- Git branch: `phase1/approval-workflow-staging`
- D1 database: `m365buddy-ai-employee-staging`
- Binding: `APPROVAL_DB`
- Admin identity: `rahulbaghel777@gmail.com`
- Cloudflare Access: Email OTP (configure Access application and policy before exposing the admin route)

## Required Cloudflare configuration
1. Create an Access self-hosted application for `m365buddy.com/admin/*` and `m365buddy.com/api/admin/*` (or protect the whole hostname with explicit public bypasses only where needed).
2. Add an Allow policy limited to the administrator email above and enable One-time PIN as the login method.
3. Add Worker variables `ACCESS_TEAM_DOMAIN` (team-name.cloudflareaccess.com) and `ACCESS_AUD` (the Access application AUD).
4. Configure staging binding `APPROVAL_DB` to the staging D1 database.
5. Set the staging deployment hostname/route and test before production.

The Worker independently validates the Cloudflare Access JWT signature, issuer, audience, expiry, and exact email claim. Do not rely only on a browser-side check.

## Email
Notifications are recorded in `notification_outbox`. Delivery is intentionally not attempted until a supported transactional sender is verified and configured. The supplied Gmail address is the recipient and requested sender identity; a Gmail From address must not be assumed valid for a transactional API provider. Configure `RESEND_API_KEY` and a verified sender address on a domain you control, then enable delivery in a later step.

## Apply migration
Run against staging only:
```sh
npx wrangler d1 migrations apply m365buddy-ai-employee-staging --remote --env staging
```

## Test checklist
- Public home, article, assistant and `POST /api/assistant` continue to work.
- Unauthenticated admin page and APIs return 401.
- Wrong Access email returns 401 even with a valid Access token.
- Correct admin OTP login can load the queue.
- Intake creates a pending item and audit event.
- Save edits draft; approve/reject updates status and audit history.
- No code path publishes content.
- Notification records remain queued until sender verification and delivery implementation.
