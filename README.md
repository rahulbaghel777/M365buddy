# M365Buddy

M365Buddy publishes practical Microsoft 365, SharePoint Online, Entra ID, PowerShell, and automation guidance.

## GitHub-powered comments

Article-level comments use Giscus backed by GitHub Discussions. Complete the one-time repository and Giscus configuration described in [Community Comments Setup](COMMUNITY_COMMENTS_SETUP.md) to activate the embedded widget. Until the category ID is configured, the site displays a fallback rather than a broken or empty comment area.

Comments are public. Never post secrets, certificates, access tokens, real tenant identifiers, internal URLs, or unredacted logs.


## M365Buddy AI Assistant

The public assistant UI is served from `public/assistant/`. Its `POST /api/assistant` endpoint is implemented in `src/index.js` and uses Cloudflare Workers AI. It retrieves up to three allowlisted M365Buddy article pages through the static-assets binding and includes them as context for answers. It can also answer broader Microsoft 365 questions from model knowledge; answers may be out of date and should be checked against current Microsoft Learn documentation.

### Deployment requirements

- Deploy from the repository root with Wrangler so `wrangler.toml`, `src/index.js`, and the `public/` assets are deployed together.
- The Wrangler config defines the `AI` Workers AI binding and `ASSETS` static-assets binding. The deployed Worker must have both bindings; a Git commit alone does not add bindings to a currently deployed Worker unless the configured deployment pipeline runs Wrangler with this configuration.
- No third-party AI API key is needed for the Workers AI binding. Usage may be subject to Cloudflare Workers AI plan limits and charges.
- The endpoint limits question length, accepted source paths, conversation history and per-isolate request rate. The in-memory rate limit is only a basic guardrail, not a substitute for a Cloudflare edge rate-limiting rule.
- Do not log or submit secrets. Do not use assistant-generated commands in production without review.

After deployment, verify `https://m365buddy.com/assistant/` and send a POST request to `/api/assistant`. Confirm that an AI binding is visible in the Worker settings. If the API returns `503`, the deployed Worker is missing the `AI` binding or has not yet been deployed with the new configuration.
