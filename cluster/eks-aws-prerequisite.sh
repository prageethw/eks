#!/bin/bash

####### create group and assign policies ######

###eks group
aws iam create-group --group-name eks


###eks group policy attach

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    --group-name eks

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --group-name eks

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
    --group-name eks

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
    --group-name eks

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess \
    --group-name kops
    
aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess \
    --group-name eks

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess \
    --group-name eks

aws iam put-group-policy \
    --group-name eks \
    --policy-name eks-kms \
    --policy-document file://resources/eks-kms-policy.json

# aws iam attach-group-policy \
#     --policy-arn $EKS_POLICY_ARN \
#     --group-name eks

################################################

####### create user and assign to the group ######
###----- eks user ----
aws iam create-user \
    --user-name eks


#wait till user really created
aws  iam  wait --user-name user-exists eks
### add user to group
aws iam add-user-to-group \
    --user-name eks \
    --group-name eks

###############################################

####### generate iam credentials specific for eks #######
mkdir -p keys
aws iam create-access-key \
    --user-name eks >keys/eks-creds

###############################################

WAIT_USER_KEY_CREATION=10

echo "Sleeping for $WAIT_USER_KEY_CREATION secs till all resources created ..."

sleep $WAIT_USER_KEY_CREATION

####### set terminal to use new eks iam ######

export AWS_ACCESS_KEY_ID=$(\
    cat keys/eks-creds | jq -r \
    '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(
    cat keys/eks-creds | jq -r \
    '.AccessKey.SecretAccessKey')

###############################################

##### generate ssh keys ##########
# remove if still exist
rm -rf keys/k8s-eks.pem
aws ec2 create-key-pair \
--key-name eks-k8s \
| jq -r '.KeyMaterial' \
>keys/k8s-eks.pem

chmod 400 keys/k8s-eks.pem
# remove if still exist
rm -rf keys/k8s-eks.pub
ssh-keygen -y -f keys/k8s-eks.pem \
    >keys/k8s-eks.pub

###################################
