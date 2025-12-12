# k3s GitOps Repository

This repository contains the GitOps configuration for the k3s cluster running on Hetzner Cloud.

## Stack

- **Flux CD** - GitOps operator
- **cert-manager** - TLS certificate management with Cloudflare DNS01
- **Traefik** - Ingress controller
- **Authentik** - SSO and identity provider
- **Linkwarden** - Bookmark manager

## Secrets Management

Secrets are encrypted using [SOPS](https://github.com/mozilla/sops) with [age](https://age-encryption.org/) encryption.

Age public key: `age16lss7f9zugtgcnuvmct4evvllznxcewq7cr6vtmpm86v5fx0dvxshxum5f`

To decrypt secrets (requires age private key):
```bash
sops -d clusters/production/cert-manager/cloudflare-secret.enc.yaml
```

## Directory Structure

```
.
├── clusters/production/        # Per-environment cluster configuration
│   ├── flux-system/           # Flux system components
│   ├── cert-manager/          # TLS certificate management
│   ├── traefik/               # Ingress controller
│   ├── authentik/             # SSO platform
│   └── linkwarden/            # Bookmark manager
└── infrastructure/
    ├── sources/               # Helm repositories
    └── configs/               # Shared configurations
```

## Bootstrap

The cluster is bootstrapped using Flux CLI:

```bash
export GITHUB_TOKEN="your-github-token"
export GITHUB_USER="cogfor"
export GITHUB_REPO="k3s-gitops"

flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=clusters/production \
  --personal
```

After bootstrap, deploy the age private key to the cluster:

```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
```

## Deployment Status

Track deployment status:

```bash
flux get all
flux get kustomizations
flux get helmreleases -A
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Comprehensive development guide including commands, architecture patterns, and workflows for working with this repository
- **[AGENTS.md](AGENTS.md)** - AI agent guidelines for repository structure and development practices
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Detailed system architecture, security design, and operational patterns
