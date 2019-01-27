# aws-eks

This repo contains files that will help you to create a K8s cluster using Kops on the fly.

## required pre-conditions

1. Install AWS CLI.
2. Install JQ.
3. Create a AWS account with admin rights.
4. Helm.
5. iam authenticator.
6. eksctl.

## set-up terminal with AWS access details

```bash
export AWS_ACCESS_KEY_ID=[...]

export AWS_SECRET_ACCESS_KEY=[...]

export AWS_DEFAULT_REGION=[...]
```

## 1.  build a kops k8s cluster

```bash

MASTER_COUNT=3  MAX_NODE_COUNT=10 MIN_NODE_COUNT=2 DESIRED_NODE_COUNT=3 NODE_SIZE=t2.small MASTER_SIZE=t2.small \
MY_ORG_DNS_NAME=example USE_HELM=true BASIC_AUTH_PWD=abcd1234 sh -x build-k8s-cluster.sh
```

**Note:**
Above command will create a cluster named example with 3 master nodes and 3 worker nodes in each AZ.

## 2.  delete cluster

```bash
sh delete-k8s-cluster.sh
```

To cleanup all AWS resources and temporary files

## 3. distribute keys

Users of can be given a package (**.zip**) file that will be generated in /cluster/keys. as part of design there are 4 types of 
such packages generated ops,dev,test and admin.

## 4. RBAC and access controls

Once users get their package, they can read README.md and point them to K8s cluster. login details for Kube dashboard,
monitoring and alerting tools will be displayed as part of context set.