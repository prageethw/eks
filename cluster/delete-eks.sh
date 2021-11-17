#!/bin/bash
set -x
source ./k8s-eks-cluster.temp
##delete Roles
aws iam delete-role --role-name eks-dev
aws iam delete-role --role-name eks-test
aws iam delete-role --role-name eks-ops
aws iam delete-role --role-name eks-admin

## delete policy
aws iam delete-group-policy --policy-name eks-dev --group-name eks-dev
aws iam delete-group-policy --policy-name eks-test --group-name eks-test
aws iam delete-group-policy --policy-name eks-ops --group-name eks-ops
aws iam delete-group-policy --policy-name eks-admin --group-name eks-admin

aws iam delete-group-policy --policy-name kms-dev --group-name eks-dev
aws iam delete-group-policy --policy-name kms-test --group-name eks-test
aws iam delete-group-policy --policy-name kms-ops --group-name eks-ops
aws iam delete-group-policy --policy-name kms-admin --group-name eks-admin

# delete users from group
aws iam remove-user-from-group \
    --user-name eks-dev \
    --group-name eks-dev
    
aws iam remove-user-from-group \
    --user-name eks-test \
    --group-name eks-test
    
aws iam remove-user-from-group \
    --user-name eks-ops \
    --group-name eks-ops
    
aws iam remove-user-from-group \
    --user-name eks-admin \
    --group-name eks-admin

# delete creds
ACCESS_KEY_ID_DEV=$(\
    cat keys/dev/eks-dev-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_DEV --user-name eks-dev
ACCESS_KEY_ID_TEST=$(\
    cat keys/test/eks-test-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_TEST --user-name eks-test
ACCESS_KEY_ID_OPS=$(\
    cat keys/ops/eks-ops-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_OPS --user-name eks-ops
ACCESS_KEY_ID_ADMIN=$(\
    cat keys/admin/eks-admin-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_ADMIN --user-name eks-admin

# delete user groups
aws iam delete-group --group-name eks-dev
aws iam delete-group --group-name eks-test
aws iam delete-group --group-name eks-ops
aws iam delete-group --group-name eks-admin

# delete users
aws iam delete-user --user-name eks-dev
aws iam delete-user --user-name eks-test
aws iam delete-user --user-name eks-ops
aws iam delete-user --user-name eks-admin

aws elb delete-load-balancer \
    --load-balancer-name $LB_NAME
aws elb delete-load-balancer \
    --load-balancer-name $ISTIO_LB_NAME
set +x
INIT_SLEEP=10
echo "Waiting $INIT_SLEEP sec for resources deleted"
echo "count down is ..."
while [ $INIT_SLEEP -gt 0 ]; do
      echo -ne "$INIT_SLEEP\033[0K\r" 
      sleep 1
      : $((INIT_SLEEP--))
done
set -x
# aws iam delete-role-policy \
#     --role-name $IAM_ROLE \
#     --policy-name nodes.$NAME-AutoScaling


# delete added nodegroups to speedup deletion
set -x
eksctl delete nodegroup --cluster=$NAME --name=$NG1_NAME --drain=false
eksctl delete nodegroup --cluster=$NAME --name=$NG2_NAME --drain=false
eksctl delete nodegroup --cluster=$NAME --name=$NG3_NAME --drain=false
set +x
INIT_SLEEP=300
echo "Waiting $INIT_SLEEP sec for NG resources deleted"
echo "count down is ..."
while [ $INIT_SLEEP -gt 0 ]; do
      echo -ne "$INIT_SLEEP\033[0K\r" 
      sleep 1
      : $((INIT_SLEEP--))
done
set -x
eksctl delete cluster -n $NAME #--wait

# delete redundent volumes
for ID in $(aws ec2 describe-volumes --filters Name=tag:kubernetes.io/cluster/$NAME,Values=owned | jq -r .Volumes[].VolumeId);
do
   aws ec2 delete-volume --volume-id $ID
done

# set +x
# # delete vpc there could be instances it can't be deleted by eksctl
# TIMES=15
# echo "Trying to delete vpc for $TIMES before giving up!"
# COUNTER=1
# aws  ec2 delete-vpc --vpc-id $VPC_NAME
# while [ $? != 0 ]; do
#     SEC_WAIT=30
#     echo "will try again in :" $SEC_WAIT "secs"
#     sleep $SEC_WAIT
#     COUNTER=$[$COUNTER +1]
#     if [ "$COUNTER" -eq $TIMES ]; then
#       break 
#     fi
#     aws  ec2 delete-vpc --vpc-id $VPC_NAME
# done

set -x
# aws cloudformation wait stack-delete-complete  --stack-name "eksctl-$NAME-cluster"
aws acm delete-certificate \
    --certificate-arn $AWS_SSL_CERT_ARN

# ##############################
# delete kms cmk
aws kms disable-key --key-id $KMS_CMK_ARN
aws kms schedule-key-deletion --key-id $KMS_CMK_ARN --pending-window-in-days 7
aws kms delete-alias --alias-name $KMS_CMK_ALIAS

set +x
INIT_SLEEP=300
echo "Waiting $INIT_SLEEP sec for NG resources deleted"
echo "count down is ..."
while [ $INIT_SLEEP -gt 0 ]; do
      echo -ne "$INIT_SLEEP\033[0K\r" 
      sleep 1
      : $((INIT_SLEEP--))
done
set -x
# delete security groups
aws ec2 delete-security-group \
    --group-id $SG_NAME
aws ec2 delete-security-group \
    --group-id $ISTIO_SG_NAME
# delete VPC
aws ec2 delete-vpc --vpc-id $VPC_NAME
# delete dhcp options

aws ec2 delete-dhcp-options --dhcp-options-id $(aws ec2 describe-dhcp-options    \
                         --filters Name=owner-id,Values=$ACCNT_ID|jq -r .DhcpOptions[].DhcpOptionsId)


#### delete kubectl config and temp files ###
set -x
rm -rf config
rm -rf k8s*
rm resources/*.temp.json
rm resources/*.temp.yaml
rm -rf keys
rm -rf *.temp.yaml
rm -rf istio-install-*
##############################
