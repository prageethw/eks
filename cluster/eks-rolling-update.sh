#!/bin/bash
source ./k8s-eks-cluster.temp
# prepare for update
export NG_PREFIX=$(date +%s)
export NG1_NEW_NAME=ng1"-"$NG_PREFIX
export NG2_NEW_NAME=ng2"-"$NG_PREFIX
export NG3_NEW_NAME=ng3"-"$NG_PREFIX

echo "New NG names are $NG1_NEW_NAME,$NG2_NEW_NAME,$NG3_NEW_NAME"

if [[ -z "${MAX_NODE_COUNT}" && -z "${NODE_TYPE}" ]]; then
    echo "You need to specify  MAX_NODE_COUNT and NODE_TYPE  before an upgrade! ..."
    exit
else
    export NODE_COUNT=$MAX_NODE_COUNT
    echo ""
    echo "Maximum nodes allowed is :" $NODE_COUNT

# update eks cluster
    eksctl update cluster --name=$NAME --approve

#----------ng1
    eksctl create nodegroup \
    --cluster $NAME \
    --name $NG1_NEW_NAME \
    --node-zones $ZONE1 \
    --node-type ${NODE_TYPE:-t2.small} \
    --nodes ${DESIRED_NODE_COUNT:-3} \
    --nodes-max ${NODE_COUNT:-5}  \
    --nodes-min ${MIN_NODE_COUNT:-3} \
    --asg-access \
    --external-dns-access \
    --ssh-access --ssh-public-key ${SSH_PUBLIC_KEY:-keys/k8s-eks.pub} 
    # --managed
#----------ng2
    eksctl create nodegroup \
    --cluster $NAME \
    --name $NG2_NEW_NAME \
    --node-zones $ZONE2 \
    --node-type ${NODE_TYPE:-t2.small} \
    --nodes ${DESIRED_NODE_COUNT:-3} \
    --nodes-max ${NODE_COUNT:-5}  \
    --nodes-min ${MIN_NODE_COUNT:-3} \
    --asg-access \
    --external-dns-access \
    --ssh-access --ssh-public-key ${SSH_PUBLIC_KEY:-keys/k8s-eks.pub} 
    # --managed
#----------ng3
    eksctl create nodegroup \
    --cluster $NAME \
    --name $NG3_NEW_NAME \
    --node-zones $ZONE3 \
    --node-type ${NODE_TYPE:-t2.small} \
    --nodes ${DESIRED_NODE_COUNT:-3} \
    --nodes-max ${NODE_COUNT:-5}  \
    --nodes-min 0 \
    --asg-access \
    --external-dns-access \
    --ssh-access --ssh-public-key ${SSH_PUBLIC_KEY:-keys/k8s-eks.pub}
    # --managed

    eksctl delete nodegroup --cluster=$NAME --name=$NG1_NAME #--drain=false
    eksctl delete nodegroup --cluster=$NAME --name=$NG2_NAME #--drain=false
    eksctl delete nodegroup --cluster=$NAME --name=$NG3_NAME #--drain=false

# To update kube-proxy, run:
    eksctl utils update-kube-proxy --cluster=$NAME
# To update aws-node, run:
    eksctl utils update-aws-node --cluster=$NAME
# To update coredns, run:
    eksctl utils update-coredns --cluster=$NAME
set +x
### wait till k8s pods comes alive
    INIT_SLEEP=60
    echo "Waiting $INIT_SLEEP sec for pods to become available..."
    echo "count down is ..."
    while [ $INIT_SLEEP -gt 0 ]; do
      echo -ne "$INIT_SLEEP\033[0K\r" 
      sleep 1
      : $((INIT_SLEEP--))
    done
######################################
set -x
# checking whether cluster ok
    kubectl get pods -n kube-system

#####################################################################
set +x
    echo ""
    echo "------------------------------------------"
    echo ""
    echo "The cluster is ready. Please execute the commands that follow to create the environment variables."
    echo ""
    echo "export NAME=$NAME"
    echo "export LB_IP=$LB_IP"
    echo "export LB_NAME=$LB_NAME"
    echo "export AWS_SSL_CERT_ARN=$AWS_SSL_CERT_ARN"
    echo "export LB_HOST=$LB_HOST"
    echo "export DOMAIN_NAME=$DOMAIN_NAME"
    echo "export ACCNT_ID=$ACCNT_ID"
    echo "export ASG_NAMES=$ASG_NAMES"
    echo "export SG_NAME=$SG_NAME"
    echo "export VPC_NAME=$VPC_NAME"
    echo "export DESIRED_NODE_COUNT=$DESIRED_NODE_COUNT"
    echo "export MIN_NODE_COUNT=$MIN_NODE_COUNT"
    echo "export PROM_ADDR=$PROM_ADDR"
    echo "export AM_ADDR=$AM_ADDR"
    echo "export EKS_POLICY_ARN=$EKS_POLICY_ARN"
    echo "export DASHBOARD_ADDR=$DASHBOARD_ADDR"
    echo "export GRAFANA_ADDR=$GRAFANA_ADDR"
    echo "export MAX_NODE_COUNT=$NODE_COUNT"
    echo "export KMS_CMK_ARN=$KMS_CMK_ARN"
    echo "export KMS_CMK_ARN_ALIAS=$KMS_CMK_ARN_ALIAS"
    echo "export KMS_CMK_ALIAS=$CMK_ALIAS"
    echo "export NG1_NAME=$NG1_NEW_NAME"
    echo "export NG2_NAME=$NG2_NEW_NAME"
    echo "export NG3_NAME=$NG3_NEW_NAME"
    echo "export ZONE1=$ZONE1"
    echo "export ZONE2=$ZONE2"
    echo "export ZONE3=$ZONE3"

    echo ""
    echo "------------------------------------------"
    echo ""

#####################################################################

#### dump important details to a temp file #####

    echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
    export NAME=$NAME
    export LB_HOST=$LB_HOST
    export LB_NAME=$LB_NAME
    export SG_NAME=$SG_NAME
    export VPC_NAME=$VPC_NAME
    export DOMAIN_NAME=$DOMAIN_NAME
    export AWS_SSL_CERT_ARN=$AWS_SSL_CERT_ARN
    export PROM_ADDR=$PROM_ADDR
    export ACCNT_ID=$ACCNT_ID
    export AM_ADDR=$AM_ADDR
    export MAX_NODE_COUNT=$NODE_COUNT
    export MIN_NODE_COUNT=$MIN_NODE_COUNT
    export GRAFANA_ADDR=$GRAFANA_ADDR
    export DASHBOARD_ADDR=$DASHBOARD_ADDR
    export EKS_POLICY_ARN=$EKS_POLICY_ARN
    export KMS_CMK_ARN=$KMS_CMK_ARN
    export KMS_CMK_ARN_ALIAS=$KMS_CMK_ARN_ALIAS
    export KMS_CMK_ALIAS=$CMK_ALIAS
    export ASG_NAMES=$ASG_NAMES
    export NG1_NAME=$NG1_NEW_NAME
    export NG2_NAME=$NG2_NEW_NAME
    export NG3_NAME=$NG3_NEW_NAME
    export ZONE1=$ZONE1
    export ZONE2=$ZONE2
    export ZONE3=$ZONE3
    export DESIRED_NODE_COUNT=$DESIRED_NODE_COUNT" \
        >k8s-eks-cluster.temp
fi
