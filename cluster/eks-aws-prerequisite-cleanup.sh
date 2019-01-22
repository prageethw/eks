#!/bin/bash

#### clean ssh key and iam key ####
set -x
aws ec2 delete-key-pair --key-name eks-k8s

ACCESS_KEY_ID_EKS=$(\
    cat keys/eks-creds | jq -r \
    '.AccessKey.AccessKeyId')

aws iam delete-access-key --access-key $ACCESS_KEY_ID_EKS --user-name eks


#######################

#### detach policies ####
aws iam detach-group-policy \
    --policy-arn $EKS_POLICY_ARN \
    --group-name eks

aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    --group-name eks
 
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --group-name eks

aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
    --group-name eks
 
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
    --group-name eks
 
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess \
    --group-name eks

aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess \
    --group-name eks

############################
# delete custom policy
aws iam delete-policy --policy-arn $EKS_POLICY_ARN

#### remove user from group ####

aws iam remove-user-from-group \
        --user-name eks \
        --group-name eks

################################

#### delete user and group #####

aws iam delete-user --user-name eks
        
aws iam delete-group --group-name eks

################################ 
