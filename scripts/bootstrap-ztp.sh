#!/usr/bin/env bash
# Extracts Red Hat's ztp-site-generate content and (optionally) points this repo's
# Argo CD Applications at your Git repo. Run this once per hub, from anywhere with
# oc/podman access to the hub.
set -euo pipefail

ensure_podman() {
  if command -v podman &>/dev/null; then return; fi
  echo "podman not found."
  if command -v dnf &>/dev/null; then
    read -rp "Install podman now via dnf? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] && sudo dnf install -y podman || { echo "Install podman manually, then re-run."; exit 1; }
  elif command -v yum &>/dev/null; then
    read -rp "Install podman now via yum? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] && sudo yum install -y podman || { echo "Install podman manually, then re-run."; exit 1; }
  else
    echo "Unsupported package manager — install podman manually (https://podman.io/docs/installation), then re-run."
    exit 1
  fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${HOME}/ocp-ztp"

read -rp "OpenShift ztp-site-generate version tag [v4.22]: " OCP_VERSION
OCP_VERSION="${OCP_VERSION:-v4.22}"

read -rp "Git repo URL for this OCP-ZTP repo (leave blank to skip patching argocd/*.yaml): " GIT_REPO_URL

read -rp "Git branch/targetRevision [main]: " GIT_BRANCH
GIT_BRANCH="${GIT_BRANCH:-main}"

echo "==> Preparing extraction directory: ${WORKDIR}/out"
mkdir -p "${WORKDIR}/out"

ensure_podman

echo "==> Logging in to registry.redhat.io"
read -rp "registry.redhat.io username: " REGISTRY_USERNAME
read -rsp "registry.redhat.io password: " REGISTRY_PASSWORD
echo
podman login registry.redhat.io -u "${REGISTRY_USERNAME}" -p "${REGISTRY_PASSWORD}"
unset REGISTRY_PASSWORD

echo "==> Extracting ztp-site-generate:${OCP_VERSION}"
podman run --log-driver=none --rm \
  "registry.redhat.io/openshift4/ztp-site-generate-rhel8:${OCP_VERSION}" \
  extract /home/ztp --tar | tar x -C "${WORKDIR}/out"

echo "==> Extracted content:"
ls -lrht "${WORKDIR}/out"

ARGOCD_PATCH="${WORKDIR}/out/argocd/deployment/argocd-openshift-gitops-patch.json"
if [[ -f "${ARGOCD_PATCH}" ]]; then
  echo "==> Patching openshift-gitops ArgoCD instance (RBAC/resource exclusions)"
  oc patch argocd openshift-gitops -n openshift-gitops --type=merge --patch-file "${ARGOCD_PATCH}"
fi

if [[ -n "${GIT_REPO_URL}" ]]; then
  echo "==> Patching repoURL/targetRevision in argocd/*.yaml"
  sed -i.bak \
    -e "s#repoURL: .*#repoURL: ${GIT_REPO_URL}#" \
    -e "s#targetRevision: .*#targetRevision: ${GIT_BRANCH}#" \
    "${REPO_ROOT}"/argocd/*.yaml
  rm -f "${REPO_ROOT}"/argocd/*.bak
fi

echo "==> Applying Hub-side GitOps ZTP deployment manifests"
oc apply -k "${WORKDIR}/out/argocd/deployment"

echo "==> Applying repo Argo CD Applications (clusters, policies, provisioning)"
oc apply -k "${REPO_ROOT}/argocd"

echo "==> Done. Check status with: oc get applications.argoproj.io -n openshift-gitops"
