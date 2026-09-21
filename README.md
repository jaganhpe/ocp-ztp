# OpenShift ZTP Lab

GitOps repository for Zero Touch Provisioning (ZTP) of OpenShift edge clusters (SNO),
managed from a hub cluster via ArgoCD (OpenShift GitOps) and RHACM/MCE Assisted Installer.

Reference stack validated for this repo (see `OpenShift_ZTP_GitOps_Customer_Deployment_Guide`):

| Component | Version |
|---|---|
| OpenShift Container Platform | 4.22.x |
| Red Hat Advanced Cluster Management (RHACM) | 2.17.x |
| Multicluster Engine (MCE) | 2.17.x |
| Red Hat OpenShift GitOps (Argo CD) | 1.21.x |
| Topology Aware Lifecycle Manager (TALM) | 4.22.x |

This repo defines each edge cluster as a single `ClusterInstance` CR (the current
SiteConfig API), rendered by the SiteConfig Operator/Assisted Service into the
underlying Namespace, BareMetalHost, NMStateConfig, InfraEnv, ClusterDeployment,
and AgentClusterInstall resources.

## Structure

```
OCP-ZTP/
├── kustomization.yaml            # Applies provisioning.yaml (synced by argocd/provisioning-app.yaml)
├── provisioning.yaml              # metal3 Provisioning CR (bare-metal, one-time hub config)
├── argocd/
│   ├── kustomization.yaml         # Applies all three Applications below
│   ├── clusters-app.yaml          # ArgoCD Application watching clusters/ (Day-1)
│   ├── policies-app.yaml          # ArgoCD Application watching policies/ (Day-2)
│   └── provisioning-app.yaml      # ArgoCD Application watching repo root (provisioning.yaml)
├── clusters/
│   ├── kustomization.yaml
│   ├── example-sno/               # Template: single-node (SNO) cluster, 1 node
│   ├── example-3node/             # Template: 3-node compact/HA cluster, 3 master nodes
│   ├── edge-sno01/                # Real SNO cluster (bonded single NIC)
│   └── edge-bond-sno02/           # Real SNO cluster (bonded dual NIC)
└── policies/
    ├── kustomization.yaml          # generators: [policy-generator.yaml]
    ├── policy-generator.yaml       # policySets, placements, and policy definitions
    ├── base-config/                # Implemented example policies (chrony, ssh-key)
    └── day2-config/                # Planned policies — see day2-config/README.md
```

### Single-node vs 3-node clusters

| | `example-sno` | `example-3node` |
|---|---|---|
| `spec.clusterType` | `SNO` | `HighlyAvailable` |
| Node count | 1 (master, runs workloads) | 3 (all master, run workloads — no dedicated workers) |
| `spec.nodes` entries | 1 | 3, each with its own `bmcAddress`/`bootMACAddress`/`nodeNetwork` |

Both use the same `ClusterInstance` API and `templateRefs`; the only differences
are `clusterType` and the number/content of `nodes` entries.

## Prerequisites (hub cluster)

This repo assumes an OpenShift cluster already exists to act as the hub
(version compatible with RHACM 2.17 / OCP 4.22, see table above). Before running
`scripts/bootstrap-ztp.sh` or applying `argocd/`, bring the hub up in this order:

1. **Storage** — install a storage operator (e.g. LVM Storage/LVMS for a single
   hub node, or OpenShift Data Foundation for HA) and ensure a default
   `StorageClass` exists:

   ```sh
   oc get storageclass
   ```

   MCE's Assisted Service needs this for its database/filesystem/image-cache
   PVCs, and ACM Observability (if enabled) needs an S3-compatible bucket. See
   the RHACM/MCE install docs for exact sizing — as a rule of thumb, budget
   100Gi+ for image storage and smaller volumes for the database/filesystem.

2. **RHACM operator** — install via OperatorHub (or a `Subscription`), then
   create a `MultiClusterHub` CR and wait for it to reach `Running`. This also
   installs Multicluster Engine (MCE) as a dependency.

3. **Assisted Service / Central Infrastructure Management** — create an
   `AgentServiceConfig` CR on MCE referencing the `StorageClass` from step 1
   for `databaseStorage`, `filesystemStorage`, and `imageStorage`.

4. **Bare-metal provisioning** — this repo's `provisioning.yaml` (applied by
   `argocd/provisioning-app.yaml`) configures the `Provisioning` CR; if your
   `HiveConfig` also needs the `AlphaAgentInstallStrategy` feature gate, patch
   it once manually (see `scripts/bootstrap-ztp.sh` output).

5. **Red Hat OpenShift GitOps** — install via OperatorHub and verify the
   default `openshift-gitops` ArgoCD instance is `Running`. Do not also install
   a community Argo CD operator on the same cluster.

6. **Topology Aware Lifecycle Manager (TALM)** — install for controlled Day-2
   policy rollout.

7. **Verify required CRDs** are present before proceeding:

   ```sh
   oc get crd | egrep "clusterinstance|infraenv|agentclusterinstall"
   ```

## Bootstrap

Run `scripts/bootstrap-ztp.sh` (from a shell with `oc` access to the hub) to
extract Red Hat's `ztp-site-generate` content, patch the `openshift-gitops` ArgoCD
instance (RBAC/resource exclusions, if the extracted content includes a patch),
patch `repoURL`/`targetRevision` in `argocd/*.yaml` to point at your Git repo, and
apply everything.

**First time after cloning this repo:**

1. Log in to the hub cluster: `oc login <hub-api-url>`
2. Podman: the script checks for it automatically and offers to install it via
   `dnf`/`yum` on RHEL/Fedora/CentOS, or prints manual install instructions
   (https://podman.io/docs/installation) and exits on other OSes.
3. Have your `registry.redhat.io` credentials ready — the script runs
   `podman login registry.redhat.io` interactively (prompts for username/password).
4. Run the script:

   ```sh
   ./scripts/bootstrap-ztp.sh
   ```

   It will prompt for:
   - the `ztp-site-generate` version tag (default `v4.22`)
   - your Git repo URL and branch (to patch `argocd/*.yaml`; leave blank to skip)

Or skip the script and apply manually (assumes `ztp-site-generate` was already
extracted and `argocd/*.yaml` already point at your repo):

```sh
oc apply -k argocd/
oc get applications.argoproj.io -n openshift-gitops
```

## Adding a new edge cluster

1. Copy `clusters/example-sno/` (single-node) or `clusters/example-3node/`
   (3-node compact) to `clusters/<cluster-name>/` and add it to
   `clusters/kustomization.yaml`.
2. Update `namespace.yaml` and `clusterinstance.yaml` with the new cluster name,
   base domain, network config, and BMC/node details.
3. Create the pull secret and BMC credentials directly on the hub, in the cluster's
   namespace (`oc create secret ...`) — never commit plaintext credentials to Git.
4. Commit and push. ArgoCD auto-syncs and RHACM begins cluster discovery/install.
5. Label the resulting `ManagedCluster` so Day-2 policies in `policies/` apply to it
   — see [policies/README.md](policies/README.md) (e.g. `clusterType=SNO`).

## Quick start: clone and deploy end-to-end

1. Fork/clone this repo and update `repoURL` in `argocd/*.yaml` if you're not
   using `https://github.com/jaganhpe/ocp-ztp.git`.
2. Complete the hub [Prerequisites](#prerequisites-hub-cluster) above.
3. Run `./scripts/bootstrap-ztp.sh` (or apply `argocd/` manually — see
   [Bootstrap](#bootstrap)).
4. For each cluster under `clusters/`, create its pull secret and BMC
   credentials secret on the hub (never commit these to Git).
5. Commit/push any cluster changes — ArgoCD syncs `clusters/` and RHACM starts
   discovery/install.
6. Once a cluster imports as a `ManagedCluster`, label it (e.g.
   `clusterType=SNO`) so the `policies/` PolicyGenerator placements bind to it.
7. Verify: `oc get applications.argoproj.io -n openshift-gitops`,
   `oc get clusterinstances -A`, `oc get policies -A`.

## References

- `OpenShift_ZTP_GitOps_Customer_Deployment_Guide` — Customer Deployment Guide covering
  hub sizing, Assisted Service/BMC provisioning, secrets, PolicyGenerator governance,
  and troubleshooting for this OCP 4.22 / RHACM 2.17 / GitOps 1.21 reference stack.
- [Implement zero-touch provisioning for OpenShift with GitOps](https://developers.redhat.com/articles/2025/07/29/implement-zero-touch-provisioning-openshift-gitops) —
  Red Hat Developer article on PolicyGenerator structure, ESO secret management, and
  Day 1/Day 2 GitOps patterns.
- [Managing OCP Infrastructures Using GitOps (Part 3)](https://myopenshiftblog.com/managing-ocp-infrastructures-using-gitops-part-3/) —
  console walkthrough of installing GitOps/TALM, patching the ArgoCD instance, and
  configuring the clusters/policies Applications.
- [adetalhouet/ocp-ztp](https://github.com/adetalhouet/ocp-ztp) — an older
  libvirt/Ironic/Sushy-based ZTP lab using manual `AgentClusterInstall`/
  `ClusterDeployment` manifests. Not used here: this repo's `ClusterInstance`/
  SiteConfig approach supersedes that manifest style.

**Note:** the `policies/` Application requires the RHACM PolicyGenerator
kustomize plugin to be enabled on the hub's ArgoCD instance (installed as part
of `ztp-site-generate`/`scripts/bootstrap-ztp.sh`) to render
`policy-generator.yaml` into `Policy`/`PlacementRule`/`PlacementBinding` objects.
