# aws-eks

This repo contains files that will help you to create a K8s cluster using eksctl on the fly.

## required pre-conditions

1. Install AWS CLI.
2. Install JQ.
3. Create a AWS account with admin rights.
4. Helm.
5. iam authenticator.
6. eksctl.
7. Kustomize
8. Istioctl
9. Mac OS

## set-up terminal with AWS access details

```bash
export AWS_ACCESS_KEY_ID=[...]

export AWS_SECRET_ACCESS_KEY=[...]

export AWS_DEFAULT_REGION=[...]
```

## 1.  build a eks k8s cluster

```bash

MASTER_COUNT=3  MAX_NODE_COUNT=10 NAME=prageethw MIN_NODE_COUNT=0 DESIRED_NODE_COUNT=1 NODE_TYPE=t3.medium MY_ORG_DNS_NAME=prageethw.com USE_HELM=true UPDATE_ISTIO_MESH="" INSTALL_ISTIO_MESH=true BASIC_AUTH_PWD=abcd1234 time sh -x build-k8s-cluster.sh

```

**Note:**
Above command will create a cluster named example with 3 master nodes and 3 worker nodes in each AZ.
BASIC_AUTH_PWD is the password you need to login to monitoring and alerting systems.To set something false pass "" as the value

## 2.  delete cluster

```bash
sh delete-k8s-cluster.sh
```

To cleanup all AWS resources and temporary files

## 3. distribute keys

Users of can be given a package (**.zip**) file that will be generated in /cluster/keys. as part of design there are 4 types of such packages generated ops,dev,test and admin.

## 4. RBAC and access controls

Once users get their package, they can read README.md and point them to K8s cluster. login details for Kube dashboard,
monitoring and alerting tools will be displayed as part of context set.

## 5. update cluster

MAX_NODE_COUNT=10  MIN_NODE_COUNT=0 DESIRED_NODE_COUNT=1 NODE_TYPE=t3.medium time sh -x update-k8s-cluster.sh
