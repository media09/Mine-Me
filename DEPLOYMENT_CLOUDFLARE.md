# Cloudflare Workers deployment

This branch deploys the Next.js application using the OpenNext Cloudflare adapter.

- Build: `npx opennextjs-cloudflare build`
- Deploy: `npx wrangler deploy`
- Runtime: Cloudflare Workers with `nodejs_compat`
- Supabase URL and publishable key are public client configuration only.
- Mining remains disabled and the global emergency pause remains enabled until the separate pool gateway and security verification are complete.

The pool gateway is a separate persistent Node.js service and is not deployed as part of this Worker.
