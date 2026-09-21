# Day-2 policies (planned, not yet implemented)

This folder is reserved for post-installation / Day-2 policies, per the
[Red Hat Developer ZTP article](https://developers.redhat.com/articles/2025/07/29/implement-zero-touch-provisioning-openshift-gitops#policy_management)
recommended layout. Candidates to add here as needed:

- `policy-alertmanager-customrule.yaml` — custom alerting rules
- `policy-file-integrity-operator.yaml` — File Integrity Operator
- `policy-ingress-certificate.yaml` — custom ingress certificate
- `policy-storagecluster.yaml` — storage configuration

Add a manifest here, then reference it under `policies:` in
[../policy-generator.yaml](../policy-generator.yaml) and add its name to the
relevant `policySets` entry.
