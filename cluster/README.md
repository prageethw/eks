# aws-kops

This repo contains files that will help you to point to a K8s cluster using Kops on the fly.

## required pre-conditions
1. Install K8s CLI.
2. Install JQ.
3. Helm.

## 1. set k8s cluster

```bash
sh  set*.sh

```


**Note:**
above command will configure your kubeconfig pointing to a k8s cluster that you can interact with.

## 2.  unset k8s cluster

```bash
sh unset*.sh

```
## 3. using helm
**Note:**
when you use helm make sure you provide --tiller-namespace as part of helm command, this will allow you to run tiller in your allocated namespace
ex:
```bash
helm upgrade -i     go-demo-3 helm/app     --namespace prod    --set image.tag=1.0     --set ingress.host=$APP_DOMAIN  --tiller-namespace=dev
```


