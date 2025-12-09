# Repository Guidelines

## Project Structure & Module Organization
The repo mirrors the k3s cluster. `clusters/production` holds per-component kustomizations such as `flux-system`, `cert-manager`, `traefik`, `linkerd`, `kyverno`, `network-policies`, and app stacks like `authentik` or `linkwarden`. Each directory keeps a `kustomization.yaml`, overlays, and encrypted manifests scoped to that workload. Shared Helm repositories sit under `infrastructure/sources`, while reusable values and CRDs live in `infrastructure/configs`. Use `templates/` as a starting point when introducing a new service.

## Build, Test, and Development Commands
```bash
flux build kustomization linkerd --path=clusters/production/linkerd
```
Dry-runs a component locally.  
```bash
flux diff kustomization linkerd --path=clusters/production/linkerd --namespace=flux-system
```
Shows the delta against the live cluster (requires cluster access).  
```bash
flux reconcile kustomization linkerd --with-source
```
Applies the change after the PR merges.  
Use `sops -d clusters/production/<comp>/secret.enc.yaml` to inspect secrets and `kubectl create secret generic sops-age ...` after rotating keys.

## Coding Style & Naming Conventions
All manifests are YAML with two-space indentation and lowercase resource names (e.g., `kustomization.yaml`, `networkpolicy-allow-dns.yaml`). Keep one workload per directory and rely on descriptive folder names that match the app or concern. Secrets must end in `.enc.yaml` and follow the schema enforced by `.sops.yaml`. When editing Helm values, group keys logically and add inline comments only for non-obvious defaults.

## Testing Guidelines
Before submitting, run `flux build` for every modified component and ensure there are no validation errors. If a change touches cluster-wide primitives (CRDs, policies), also run `flux build kustomization flux-system`. With cluster access, use `flux diff` to confirm rendered manifests match expectations, then `flux get kustomizations` to verify reconciliation status. Prefer adding Kyverno or NetworkPolicy tests by cloning the component into `templates/` and leveraging `kubectl --dry-run=client apply -k <dir>`.

## Commit & Pull Request Guidelines
Commits should be short, imperative statements (e.g., `Add NetworkPolicies for LDAP outpost`), mirroring current history. Squash fixups so each commit represents a deployable unit. PRs need a summary of the user-facing effect, linked issue or ticket numbers, and screenshots or command output for risky changes (e.g., `flux diff`). Always call out required secret rotations or Flux bootstrap steps in the description.
