# aws-kops

This repo contains files that will help you to create a K8s cluster using Kops on the fly.

## required pre-conditions

1. Install AWS CLI.
2. Install JQ.
3. Create a AWS account.
4. Helm.

## set-up terminal with AWS access details

```bash
export AWS_ACCESS_KEY_ID=[...]

export AWS_SECRET_ACCESS_KEY=[...]

export AWS_DEFAULT_REGION=[...]
```

## 1.  build a kops k8s cluster

```bash

MASTER_COUNT=3  MAX_NODE_COUNT=10 MIN_NODE_COUNT=2 DESIRED_NODE_COUNT=3 NODE_SIZE=t2.small MASTER_SIZE=t2.small MY_ORG_DNS_NAME=example.k8s.local USE_HELM=true BASIC_AUTH_PWD=abcd1234 sh -x build-k8s-cluster.sh
```

**Note:**
above command will create a cluster named example.com.au.k8s.local with 3 master nodes and 3 worker nodes.

## 2.  delete cluster

```bash
sh delete-k8s-cluster.sh
```

To cleanup all AWS resources and temporary files

## 3. dry run

```bash
MASTER_COUNT=3 NODE_COUNT=3 NODE_SIZE=t2.small MASTER_SIZE=t2.small DRY_RUN=true MY_ORG_DNS_NAME=example.k8s.local USE_HELM=true sh -x build-k8s-cluster.sh
sh delete-k8s-cluster.sh
```
