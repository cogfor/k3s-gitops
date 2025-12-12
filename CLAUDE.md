# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a production k3s GitOps cluster managed by Flux CD with Zero Trust networking (Linkerd service mesh, NetworkPolicies), policy enforcement (Kyverno), and encrypted secrets (SOPS with age). All cluster state is declarative and stored in Git.

## Key Commands

### Validate Changes Locally
```bash
# Dry-run a component locally (no cluster access needed)
flux build kustomization <component> --path=clusters/production/<component>

# Example:
flux build kustomization linkerd --path=clusters/production/linkerd
```

### Preview Changes Against Live Cluster
```bash
# Show diff between local changes and deployed state (requires cluster access)
flux diff kustomization <component> --path=clusters/production/<component> --namespace=flux-system

# Example:
flux diff kustomization authentik --path=clusters/production/authentik --namespace=flux-system
```

### Apply Changes
```bash
# Force reconciliation after merging changes
flux reconcile kustomization <component> --with-source

# Example:
flux reconcile kustomization linkerd --with-source
```

### Check Deployment Status
```bash
# View all Flux resources
flux get all

# Check kustomization status
flux get kustomizations

# Check HelmRelease status across all namespaces
flux get helmreleases -A

# View Flux logs (useful for debugging)
flux logs --level=error
```

### Secrets Management
```bash
# Decrypt a SOPS-encrypted secret (requires age private key at ~/.config/sops/age/keys.txt)
sops -d clusters/production/<component>/<secret>.enc.yaml

# Encrypt a new secret
sops -e --in-place clusters/production/<component>/<secret>.yaml

# Edit encrypted secret in-place
sops clusters/production/<component>/<secret>.enc.yaml
```

### Debugging
```bash
# Check pod status
kubectl get pods -n <namespace>

# View logs (including crashed containers)
kubectl logs -n <namespace> deployment/<name> --previous

# Describe pod for events
kubectl describe pod -n <namespace> <pod-name>

# Check NetworkPolicies
kubectl get netpol -n <namespace>
kubectl describe netpol -n <namespace> <policy-name>

# Debug network connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot -n <namespace> -- bash

# Check Linkerd proxy status
linkerd check --proxy -n <namespace>

# View service mesh metrics
linkerd viz stat deploy -n <namespace>
linkerd viz tap deploy/<name> -n <namespace>

# Check Linkerd identity
linkerd identity -n <namespace>
```

## Architecture

### Repository Structure

- `clusters/production/`: Cluster-specific configuration
  - `flux-system/`: Flux CD controllers and component kustomizations (deployment order)
    - `gotk-components.yaml`: Flux installation manifests
    - `gotk-sync.yaml`: Git repository sync configuration
    - `<component>-kustomization.yaml`: Flux Kustomization CRDs (one per component)
  - `<component>/`: Individual application/service directories (authentik, linkerd, traefik, etc.)
    - `kustomization.yaml`: Local kustomize configuration
    - `namespace.yaml`: Namespace definition
    - `helmrelease.yaml`: Helm chart deployment (if applicable)
    - `*.enc.yaml`: SOPS-encrypted secrets
    - `networkpolicy-*.yaml`: NetworkPolicy definitions
- `infrastructure/`: Shared resources
  - `sources/`: HelmRepository CRDs
  - `cert-manager-config/`: ClusterIssuer definitions

### Component Deployment Order

Flux Kustomizations in `clusters/production/flux-system/` define dependencies via `spec.dependsOn`. The typical order is:

1. `sources` (Helm repositories)
2. `cert-manager` → `cert-manager-issuers`
3. `traefik` (ingress controller)
4. `linkerd` (service mesh, requires cert-manager for mTLS certificates)
5. `kyverno` → `kyverno-policies`
6. `network-policies` (default-deny NetworkPolicies)
7. Applications: `authentik`, `linkwarden`, `tailscale`, `monitoring`, `backup`

### Security Layers

1. **Network Segmentation**: Default-deny NetworkPolicies with explicit allow rules per service
2. **Identity & mTLS**: Linkerd provides automatic mutual TLS between pods (zero-config)
3. **Policy Enforcement**: Kyverno validates resources (currently audit mode, logs violations but doesn't block)
4. **Secrets Encryption**: All secrets encrypted with SOPS (age key), decrypted by Flux at deployment time
5. **TLS**: Let's Encrypt for external traffic (cert-manager + Cloudflare DNS-01), Linkerd mTLS for internal

### Storage

- **StorageClass**: `local-path` (k3s built-in, hostPath-based)
- **Limitations**: Single-node, no replication, no automated backups
- **Databases**: PostgreSQL and Redis with persistent volumes (10Gi authentik-postgres, 8Gi authentik-redis, 5Gi linkwarden-postgres)

## Important Patterns

### Adding a New Component

1. Create directory: `clusters/production/<component>/`
2. Add required files:
   - `kustomization.yaml` (kustomize config)
   - `namespace.yaml` (namespace definition)
   - `helmrelease.yaml` (if using Helm) or raw manifests
   - `networkpolicy-*.yaml` (NetworkPolicies for ingress/egress)
3. Encrypt secrets: `sops -e --in-place <secret>.yaml` (renames to `.enc.yaml`)
4. Create Flux Kustomization: `clusters/production/flux-system/<component>-kustomization.yaml`
   - Set `spec.dependsOn` to ensure proper deployment order
   - Enable SOPS decryption if needed:
     ```yaml
     decryption:
       provider: sops
       secretRef:
         name: sops-age
     ```
5. Reference in `clusters/production/flux-system/kustomization.yaml`

### Enabling Linkerd for a Component

Add annotation to pod spec (Deployment, StatefulSet, etc.):
```yaml
spec:
  template:
    metadata:
      annotations:
        linkerd.io/inject: enabled
```

Linkerd will automatically inject sidecar proxies and establish mTLS.

### NetworkPolicy Best Practices

- Start with default-deny in namespace
- Allow DNS egress: `podSelector: {}` → `port: 53` → `namespaceSelector: kube-system`
- Allow Linkerd control plane: port 8443 to linkerd namespace
- Allow Kubernetes API: port 443/6443 to kube-system
- Use specific pod selectors and port numbers (avoid wildcards)
- Test connectivity after applying policies

### SOPS Secret Format

Encrypted secrets must have `data` or `stringData` fields encrypted (per `.sops.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example
  namespace: example
type: Opaque
data:
  password: <base64-encoded-and-encrypted>
```

Run `sops -e --in-place secret.yaml` to encrypt. Flux will decrypt automatically during reconciliation.

### Kustomization Dependencies

Always set `spec.dependsOn` in Flux Kustomizations to enforce ordering:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: authentik
  namespace: flux-system
spec:
  dependsOn:
    - name: traefik
    - name: linkerd
    - name: network-policies
```

This prevents race conditions (e.g., deploying app before ingress controller is ready).

## YAML Style

- Two-space indentation
- Lowercase filenames with hyphens (`networkpolicy-allow-dns.yaml`)
- One workload per directory
- Descriptive resource names matching folder/component
- Inline comments only for non-obvious configurations
- All manifests start with `---` separator

## Testing Changes

Before submitting PRs:

1. Run `flux build kustomization <component>` for every modified component
2. Verify no validation errors
3. If changing cluster-wide resources (CRDs, policies): `flux build kustomization flux-system`
4. With cluster access: `flux diff kustomization <component>` to preview changes
5. After merge: `flux reconcile kustomization <component> --with-source`

## Known Limitations

- Single-node cluster (no HA)
- Local storage only (no replication)
- No automated backups (Velero not yet implemented)
- Kyverno in audit mode (logs violations, doesn't enforce)
- Manual Cloudflare DNS management
