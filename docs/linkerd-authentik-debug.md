# Authentik + Linkerd Mesh Debug Notes

## Current Status

- Authentik must remain **off-mesh** for now (`linkerd.io/inject: "disabled"` on the namespace, deployments, and statefulsets) to keep the mail service stable.
- Previous attempts to re-enable Linkerd added:
  - Pod annotations for opaque ports / skip outbound overrides.
  - `Server`/`ServerAuthorization` resources protecting Postgres/Redis.
  - Namespace pod-security overrides so Linkerd’s init container can program iptables.
- Even with those manifests applied the Authentik pods still logged repeated `PostgreSQL connection failed ... server closed the connection unexpectedly` and Postgres’ Linkerd proxy reported `tls=None (NoClientHello)` meaning the outbound proxies never established mTLS.

## Findings

1. **NetworkPolicies** were not the bottleneck. iptables/ipset dumps confirmed kube-router accepted the flows.
2. **Linkerd proxies failed before dialing Postgres.** Proxy metrics showed only `peer="src"` traffic; no downstream `peer="dst"` connections opened, and the Postgres proxy denied plaintext sessions.
3. **Control-plane lookups were flaky.** Logs periodically showed `linkerd_stack::failfast` and inability to fetch destinations/policy, suggesting the proxies couldn’t talk to linkerd-destination/policy reliably (possibly due to kube-router ordering).
4. **Namespace PSP requirements blocked proxy-init** until pod-security labels were relaxed.

## Next Steps (Test Namespace Plan)

1. **Create a dedicated staging namespace** (e.g., `authentik-mesh-lab`) with Linkerd injection enabled from the start, independent of production secrets.
2. **Deploy a minimal workload**:
   - Dummy application Deployment with Linkerd injection.
   - Postgres StatefulSet (with ClusterIP service) plus Redis if needed.
3. **Apply the same Linkerd policies** (Server + ServerAuthorization) and tighten network policies incrementally to mimic production.
4. **Instrument the lab namespace**:
   - Run `linkerd tap`, `linkerd diagnostics proxy-metrics`, and `tcpdump` inside pods while sending traffic to verify when TLS is negotiated.
   - Capture linkerd-destination / linkerd-policy logs to detect denied requests or TokenReview errors.
5. **Experiment with policy permutations**:
   - Temporarily set `proxyProtocol: Unknown` and `ServerAuthorization` to allow unauthenticated clients to confirm basic routing.
   - Gradually enforce MeshTLS service accounts once connectivity works.
6. **Document a clean rollout recipe** once the staged environment proves stable, then reapply to production.

Until the staged setup proves the Linkerd mTLS path end-to-end, keep the production Authentik namespace off-mesh.
