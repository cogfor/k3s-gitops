# Umami analytics

The tracker script and collection endpoint are exposed at `https://analytics.cirthe.com`.

The dashboard is available only through Tailscale at `https://umami.tail6cd0b8.ts.net`.

After the first deployment, sign in through Tailscale with the default `admin` / `umami` credentials and change the password immediately.

Add `cirthe.com` as the first website in the Umami dashboard.

Use the generated website ID and the following values in the Cirthe website repository's production build environment:

```text
PUBLIC_UMAMI_SCRIPT_URL=https://analytics.cirthe.com/script.js
PUBLIC_UMAMI_WEBSITE_ID=<the-Umami-website-ID-for-cirthe.com>
```

Additional websites can be added in Umami without changing the Kubernetes workload.
