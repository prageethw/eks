#!/bin/bash

#### set kops env ####

source ./set-eks.env

if [[ -z "${MY_ORG_DNS_NAME}" && -z "${MAX_NODE_COUNT}" && -z "${BASIC_AUTH_PWD}" &&  -z "${NAME}" ]]; then

    echo "You need to specify MY_ORG_DNS_NAME , MAX_NODE_COUNT , BASIC_AUTH_PWD and NAME at minimum"
    exit
else
    ###custom iam policy for eks
    export NAME=$NAME-$(date +%s)
    export DOMAIN_NAME=$MY_ORG_DNS_NAME
    export BASIC_AUTH_PWD
    export ACCNT_ID=$(aws sts get-caller-identity --output text --query Account)
    # create kms cmk
    export KMS_CMK_ARN=$(aws kms create-key --description "kms master key to encrypt/decrypt helm secrets" | jq -r '.KeyMetadata.Arn')
    #alias for CMK
    export CMK_ALIAS="alias/helm-enc-dec-kms-cmk"-$(date +%s)
    aws kms create-alias --alias-name $CMK_ALIAS --target-key-id $KMS_CMK_ARN    
    aws kms enable-key-rotation --key-id $KMS_CMK_ARN
    KMS_CMK_ARN_ALIAS=$KMS_CMK_ARN
    KMS_CMK_ARN_ALIAS="${KMS_CMK_ARN_ALIAS%%:key*}"
    export KMS_CMK_ARN_ALIAS="$KMS_CMK_ARN_ALIAS:$CMK_ALIAS"
    
    #-------
    export EKS_POLICY_ARN=$(aws iam create-policy --policy-name eks-policy --policy-document file://resources/eks-policy.json | jq -r '.Policy.Arn')
    echo "The policy ARN " $EKS_POLICY_ARN
    echo "The selected k8s cluster name is :" $NAME
    export AWS_SSL_CERT_ARN=$(\
         aws acm request-certificate \
           --domain-name "$MY_ORG_DNS_NAME" \
           --validation-method DNS \
           --idempotency-token 91adc45q667788 \
           --options CertificateTransparencyLoggingPreference=ENABLED \
           --subject-alternative-names "*.$MY_ORG_DNS_NAME"  "*.cluster.$MY_ORG_DNS_NAME"  "cluster.$MY_ORG_DNS_NAME" \
              "*.dev.cluster.$MY_ORG_DNS_NAME"  "dev.cluster.$MY_ORG_DNS_NAME"  \
              "*.test.cluster.$MY_ORG_DNS_NAME"  "test.cluster.$MY_ORG_DNS_NAME" | jq -r \
              '.CertificateArn')
    echo "ssl cert arn is :" $AWS_SSL_CERT_ARN
    export NODE_COUNT=$MAX_NODE_COUNT
    echo ""
    echo "Maximum nodes allowed is :" $NODE_COUNT

fi
export NG1_NAME=ng1
export NG2_NAME=ng2
export NG3_NAME=ng3
IFS=',' read -ra ADDR <<< "$ZONES"
j=1
for i in "${ADDR[@]}"; do
    export ZONE$j=$i
    ((j++))
done

### set kubeconfig

export KUBECONFIG=keys/kubecfg-eks

#### create eks cluster ####
    eksctl create cluster \
    -n $NAME \
    -r $AWS_DEFAULT_REGION \
    --kubeconfig keys/kubecfg-eks \
    --node-type ${NODE_TYPE:-t2.small} \
    --nodes ${DESIRED_NODE_COUNT:-3} \
    --nodes-max ${NODE_COUNT:-5}  \
    --nodes-min ${MIN_NODE_COUNT:-3} \
    --asg-access \
    --without-nodegroup \
    --external-dns-access \
    --ssh-access --ssh-public-key ${SSH_PUBLIC_KEY:-keys/k8s-eks.pub} \
    --version=1.14
    # --tags "k8s.io/cluster-autoscaler/enabled=true" \
### add additional node groups to resolve volume bidning issues.NOTE: tags not supported still for nodegroups

#----------ng1
    eksctl create nodegroup \
    --cluster $NAME \
    --name $NG1_NAME \
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
    --name $NG2_NAME \
    --node-zones $ZONE2 \
    --node-type ${NODE_TYPE:-t2.small} \
    --nodes ${DESIRED_NODE_COUNT:-3} \
    --nodes-max ${NODE_COUNT:-5}  \
    --nodes-min ${MIN_NODE_COUNT:-3} \
    --asg-access \
    --external-dns-access \
    --ssh-access --ssh-public-key ${SSH_PUBLIC_KEY:-keys/k8s-eks.pub} 
    # --managed
# --node-zones $ZONE2 \
#----------ng3
    eksctl create nodegroup \
    --cluster $NAME \
    --name $NG3_NAME \
    --node-zones $ZONE3 \
    --node-type ${NODE_TYPE:-t2.small} \
    --nodes ${DESIRED_NODE_COUNT:-3} \
    --nodes-max ${NODE_COUNT:-5}  \
    --nodes-min 0 \
    --asg-access \
    --external-dns-access \
    --ssh-access --ssh-public-key ${SSH_PUBLIC_KEY:-keys/k8s-eks.pub} 
    # --managed
# --node-zones $ZONE3 \
# --node-labels "chaos-gorilla=true" \


#patch dns to support CA
    kubectl apply -f ./resources/core-dns-pdb.yaml
#create namespaces
    kubectl apply -f resources/cluster-namespaces.yaml
############enable rbac and user creation #####    
     sh set-up-k8s-users.sh
#########################################

#### intall ingress ####

    wget -O- -q https://raw.githubusercontent.com/prageethw/kops/master/addons/ingress-nginx/v1.6.0-aws-http-ssl-redirect-with-hpa-pdb.yaml>k8s.nginx.yaml
    #replace with valid certificate arn
    cat k8s.nginx.yaml  | sed -e     "s@ARN@$AWS_SSL_CERT_ARN@g" |     tee k8s.nginx.yaml
    kubectl apply -f k8s.nginx.yaml
    kubectl -n kube-ingress rollout status deployment ingress-nginx

###############################################################

### wait till nginx ELB comes alive
    ELB_INIT_SLEEP=60
    echo "Waiting $ELB_INIT_SLEEP sec for ELB to become available..."
    echo "count down is ..."
    while [ $ELB_INIT_SLEEP -gt 0 ]; do
      echo -ne "$ELB_INIT_SLEEP\033[0K\r" 
      sleep 1
      : $((ELB_INIT_SLEEP--))
    done
######################################

#########modify asg group####### 
 
    export LB_HOST=$(kubectl -n kube-ingress \
        get svc ingress-nginx \
        -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")

    export LB_IP="$(dig +short $LB_HOST | tail -n 1)"

    export LB_NAME=$(aws elb \
    describe-load-balancers \
    | jq -r \
    ".LoadBalancerDescriptions[0] \
    | select(.SourceSecurityGroup.GroupName \
    | contains (\"k8s-elb\")) \
    .LoadBalancerName")

    echo "Waiting for ELB to become available..."
    echo ""
    
    aws elb wait  instance-in-service \
                      --load-balancer-name $LB_NAME

    # export ASG_NAME="$(aws autoscaling \
    # describe-auto-scaling-groups \
    # | jq -r ".AutoScalingGroups[0] \
    # | select(.AutoScalingGroupName \
    # | startswith(\"eksctl-$NAME-nodegroup\")) \
    # .AutoScalingGroupName")"

    export SG_NAME=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=k8s-elb-$LB_NAME \
    | jq -r ".SecurityGroups[0].GroupId")

    export VPC_NAME=$(aws ec2 \
    describe-vpcs \
    | jq -r \
    ".Vpcs[0].VpcId")




# # note : below commented out as eksctl provides abilty of tagging and enabeling autoscaling using flags
    # export IAM_ROLE=$(aws iam list-roles \
    # | jq -r ".Roles[] \
    # | select(.RoleName \
    # | startswith(\"eksctl-$NAME-nodeg\")) \
    # .RoleName")
#  ## patch iam role to interact with AWS ASG 
#     aws iam put-role-policy \
#     --role-name $IAM_ROLE \
#     --policy-name nodes.$NAME-AutoScaling \
#     --policy-document file://resources/eks-autoscaling-policy.json
# #############################################
#     #tag instances so kubernetes can figure it out to be safe
#     for ID in $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --query AutoScalingGroups[].Instances[].InstanceId --output text);
#     do
#        aws ec2  create-tags --resources $ID --tags Key=k8s.io/cluster-autoscaler/enabled,Value=true Key=kubernetes.io/cluster/$NAME,Value=true
#     done
#     #tag ASG group incase to be safe
#     aws autoscaling \
#     create-or-update-tags \
#     --tags \
#     ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
#     ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=kubernetes.io/cluster/$NAME,Value=true,PropagateAtLaunch=true
  
# ###########################################
# enabeling multi nodegroup clusters
ASG_NAMES=""
for ASG_NAME in $(aws autoscaling describe-auto-scaling-groups | jq -r ".AutoScalingGroups[] | select(.AutoScalingGroupName | startswith(\"eksctl-$NAME-nodegroup\")).AutoScalingGroupName");
do
#    for ID in $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --query AutoScalingGroups[].Instances[].InstanceId --output text);
#    do
#      aws ec2  create-tags --resources $ID --tags Key=k8s.io/cluster-autoscaler/enabled,Value=true Key=kubernetes.io/cluster/$NAME,Value=true
#    done
#    aws autoscaling create-or-update-tags \
#     --tags \
#     ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
#     ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=kubernetes.io/cluster/$NAME,Value=true,PropagateAtLaunch=true
    ASG_NAMES=$ASG_NAME,$ASG_NAMES
done
    export ASG_NAMES=${ASG_NAMES%?}


#### install helm if required ####

    if [[ ! -z "${USE_HELM}" ]]; then
        kubectl create -f resources/tiller-rbac.yml --record --save-config
        helm init --service-account tiller
        helm init --service-account tiller-dev --tiller-namespace dev
        helm init --service-account tiller-test --tiller-namespace test 
        helm init --service-account tiller-ops --tiller-namespace ops
        #delete service and only allow CLI helm comms , security patch as suggested here https://engineering.bitnami.com/articles/helm-security.html
        kubectl -n kube-system delete service tiller-deploy
        kubectl -n dev delete service tiller-deploy
        kubectl -n test delete service tiller-deploy
        kubectl -n ops delete service tiller-deploy
        kubectl -n kube-system patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n dev patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n test patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n ops patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n kube-system rollout status deploy tiller-deploy
        kubectl -n dev rollout status deploy tiller-deploy
        kubectl -n test rollout status deploy tiller-deploy
        kubectl -n ops rollout status deploy tiller-deploy
        kubectl apply -f resources/tiller-hpa.yaml
        kubectl apply -f resources/tiller-pdb.yaml
        
    fi

############################################


################################################################

    export PROM_ADDR=monitor.cluster.$DOMAIN_NAME
    export AM_ADDR=alertmanager.cluster.$DOMAIN_NAME
    export GRAFANA_ADDR=grafana.cluster.$DOMAIN_NAME
    export DASHBOARD_ADDR=kubernetes-dashboard.cluster.$DOMAIN_NAME
    export MESH_GRAFANA_ADDR=mesh-grafana.cluster.$DOMAIN_NAME
    export MESH_PROM_ADDR=mesh-monitor.cluster.$DOMAIN_NAME
    export MESH_KIALI_ADDR=mesh-kiali.cluster.$DOMAIN_NAME
    export MESH_JAEGER_ADDR=mesh-jaeger.cluster.$DOMAIN_NAME

#####install istio crds to enable external DNS to support istio gateway#######
     echo "installing istio crds "
     echo ""
     kubectl apply -f resources/istio/base/istio-crds.yaml
     echo ""

################################################################

#######install tools ###########################################

     echo "installing required tools"
     echo ""
     sh tools.sh
     echo ""

################################################################

    if [[ ! -z "${INSTALL_ISTIO_MESH}" ]]; then
        ./set-up-istio.sh
    fi
##### SSL offloading ########

     aws acm wait certificate-validated \
               --certificate-arn $AWS_SSL_CERT_ARN
    
#################################

#####################################################################

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
echo "export NG1_NAME=$NG1_NAME"
echo "export NG2_NAME=$NG2_NAME"
echo "export NG3_NAME=$NG3_NAME"
echo "export ZONE1=$ZONE1"
echo "export ZONE2=$ZONE2"
echo "export ZONE3=$ZONE3"
echo "export MESH_GRAFANA_ADDR=$MESH_GRAFANA_ADDR"
echo "export MESH_PROM_ADDR=$MESH_PROM_ADDR"
echo "export MESH_KIALI_ADDR=$MESH_KIALI_ADDR"
echo "export MESH_JAEGER_ADDR=$MESH_JAEGER_ADDR"

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
export NG1_NAME=$NG1_NAME
export NG2_NAME=$NG2_NAME
export NG3_NAME=$NG3_NAME
export ZONE1=$ZONE1
export ZONE2=$ZONE2
export ZONE3=$ZONE3
export DESIRED_NODE_COUNT=$DESIRED_NODE_COUNT
export MESH_GRAFANA_ADDR=$MESH_GRAFANA_ADDR
export MESH_PROM_ADDR=$MESH_PROM_ADDR
export MESH_KIALI_ADDR=$MESH_KIALI_ADDR
export MESH_JAEGER_ADDR=$MESH_JAEGER_ADDR" \
    >k8s-eks-cluster.temp
echo "the cluster KUBECONFIG logged in to $PWD/keys/kubecfg-eks ..."
########################################################################
