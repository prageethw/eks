# aws-kops

This repo contains files that will help you to point to a K8s cluster using Kops on the fly.

## required pre-conditions

1. Install K8s CLI.
2. Install JQ.
3. Helm 3.
4. IAM authenticator.
5. Kustomize
6. Istioctl

## 1. set k8s cluster

```bash
sh  set*.sh

```

**Note:**
Above command will provide your kubeconfig details and default iam details to a k8s cluster that you can interact with.