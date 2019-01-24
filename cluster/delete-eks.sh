#!/bin/bash
set -x
##delete Roles
aws iam delete-role --role-name eks-dev
aws iam delete-role --role-name eks-test
aws iam delete-role --role-name eks-ops
aws iam delete-role --role-name eks-admin

## DELETE policy
aws iam delete-group-policy --policy-name eks-dev --group-name eks-dev
aws iam delete-group-policy --policy-name eks-test --group-name eks-test
aws iam delete-group-policy --policy-name eks-ops --group-name eks-ops
aws iam delete-group-policy --policy-name eks-admin --group-name eks-admin

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

# aws iam delete-role-policy \
#     --role-name $IAM_ROLE \
#     --policy-name nodes.$NAME-AutoScaling

# delete added nodegroups to speedup deletion

eksctl delete nodegroup --cluster=$NAME --name=$NG1_NAME
eksctl delete nodegroup --cluster=$NAME --name=$NG2_NAME
eksctl delete nodegroup --cluster=$NAME --name=$NG3_NAME

eksctl delete cluster -n $NAME #--wait

aws ec2 delete-security-group \
    --group-id $SG_NAME

# aws  ec2 delete-vpc --vpc-id $VPC_NAME

# aws cloudformation wait stack-delete-complete  --stack-name "eksctl-$NAME-cluster"

aws acm delete-certificate \
    --certificate-arn $AWS_SSL_CERT_ARN

# ##############################

#### delete kubectl config ###

rm -rf config
rm -rf k8s*
rm resources/*.temp.json
rm resources/*.temp.yaml
rm -rf keys
rm kubecfg-eks
##############################