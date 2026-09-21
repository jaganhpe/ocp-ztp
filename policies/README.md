# Day-2 policy management (RHACM PolicyGenerator)

Policies applied to managed clusters after ZTP install are defined here using
the [RHACM PolicyGenerator](https://github.com/stolostron/policy-generator-plugin),
following the layout recommended in the
[Red Hat Developer ZTP article](https://developers.redhat.com/articles/2025/07/29/implement-zero-touch-provisioning-openshift-gitops#policy_management).

## Structure

```
policies/
├── kustomization.yaml       # generators: [policy-generator.yaml]
├── policy-generator.yaml    # policySets, placements, and policy definitions
├── base-config/             # implemented example policies (chrony, ssh-key)
└── day2-config/             # planned policies (see day2-config/README.md)
```

## How it works

- `policy-generator.yaml` defines `policySets` (named groups of policies bound
  to a `placement`), and `policies` (each pointing at a manifest path).
- `global` policySet targets every managed cluster with the `vendor: OpenShift`
  label (set automatically by RHACM on import).
- `sno` policySet targets clusters labeled `clusterType: SNO` — add this label
  manually to the `ManagedCluster` after import:

  ```sh
  oc label managedcluster <cluster-name> clusterType=SNO
  ```

## Adding a new policy

1. Add the manifest (e.g. a `MachineConfig`, `ConfigMap`, or Operator CR) under
   `base-config/` or `day2-config/`.
2. Add an entry under `policies:` in `policy-generator.yaml` referencing the
   manifest path.
3. Add the policy name to the relevant `policySets[].policies` list.

## Prerequisite

Rendering `policy-generator.yaml` requires the RHACM PolicyGenerator kustomize
plugin to be enabled on the hub's ArgoCD instance (`policy-generator-plugin`,
delivered via `ztp-site-generate`/`scripts/bootstrap-ztp.sh`). Without it, ArgoCD
cannot expand this file into `Policy`/`PlacementRule`/`PlacementBinding` objects.
