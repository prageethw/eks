#!/bin/bash

#create user groups
aws iam create-group --group-name eks-dev
aws iam create-group --group-name eks-test
aws iam create-group --group-name eks-ops
aws iam create-group --group-name eks-admin

#create users
export DEV_USER_ARN=$(aws iam create-user --user-name eks-dev | jq -r .User.Arn)
export TEST_USER_ARN=$(aws iam create-user --user-name eks-test | jq -r .User.Arn)
export OPS_USER_ARN=$(aws iam create-user --user-name eks-ops | jq -r .User.Arn)
export ADMIN_USER_ARN=$(aws iam create-user --user-name eks-admin | jq -r .User.Arn)

#add users to the group
aws iam add-user-to-group \
    --user-name eks-dev \
    --group-name eks-dev
    
aws iam add-user-to-group \
    --user-name eks-test \
    --group-name eks-test
    
aws iam add-user-to-group \
    --user-name eks-ops \
    --group-name eks-ops
    
aws iam add-user-to-group \
    --user-name eks-admin \
    --group-name eks-admin

#create policy doc
cat resources/assume-dev-eks-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/assume-dev-eks-iam-role-policy.temp.json
cat resources/assume-test-eks-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/assume-test-eks-iam-role-policy.temp.json
cat resources/assume-ops-eks-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/assume-ops-eks-iam-role-policy.temp.json
cat resources/assume-admin-eks-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/assume-admin-eks-iam-role-policy.temp.json
#create roles
export DEV_ROLE_ARN=$(aws iam create-role --role-name eks-dev --assume-role-policy-document file://resources/assume-dev-eks-iam-role-policy.temp.json | jq -r .Role.Arn)
export TEST_ROLE_ARN=$(aws iam create-role --role-name eks-test --assume-role-policy-document file://resources/assume-test-eks-iam-role-policy.temp.json | jq -r .Role.Arn)
export OPS_ROLE_ARN=$(aws iam create-role --role-name eks-ops --assume-role-policy-document file://resources/assume-ops-eks-iam-role-policy.temp.json | jq -r .Role.Arn)
export ADMIN_ROLE_ARN=$(aws iam create-role --role-name eks-admin --assume-role-policy-document file://resources/assume-admin-eks-iam-role-policy.temp.json | jq -r .Role.Arn)
#create group policy
cat resources/dev-eks-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/dev-eks-iam-policy.temp.json
cat resources/test-eks-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/test-eks-iam-policy.temp.json
cat resources/ops-eks-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/ops-eks-iam-policy.temp.json
cat resources/admin-eks-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee resources/admin-eks-iam-policy.temp.json
#assign group policy to the groups
aws iam put-group-policy \
    --group-name eks-dev \
    --policy-name eks-dev \
    --policy-document file://resources/dev-eks-iam-policy.temp.json
aws iam put-group-policy \
    --group-name eks-test \
    --policy-name eks-test \
    --policy-document file://resources/test-eks-iam-policy.temp.json
aws iam put-group-policy \
    --group-name eks-ops \
    --policy-name eks-ops\
    --policy-document file://resources/ops-eks-iam-policy.temp.json
aws iam put-group-policy \
    --group-name eks-admin \
    --policy-name eks-admin \
    --policy-document file://resources/admin-eks-iam-policy.temp.json


#assign kms cmk to roles

aws iam put-group-policy \
    --group-name eks-dev \
    --policy-name kms-dev \
    --policy-document file://resources/user-kms-policy.json
aws iam put-group-policy \
    --group-name eks-test \
    --policy-name kms-test \
    --policy-document file://resources/user-kms-policy.json
aws iam put-group-policy \
    --group-name eks-ops \
    --policy-name kms-ops \
    --policy-document file://resources/user-kms-policy.json
aws iam put-group-policy \
    --group-name eks-admin \
    --policy-name kms-admin \
    --policy-document file://resources/user-kms-policy.json

##download keys

mkdir -p keys/dev
aws iam create-access-key --user-name eks-dev >keys/dev/eks-dev-creds
mkdir -p keys/test
aws iam create-access-key --user-name eks-test >keys/test/eks-test-creds
mkdir -p keys/ops
aws iam create-access-key --user-name eks-ops >keys/ops/eks-ops-creds
mkdir -p keys/admin
aws iam create-access-key --user-name eks-admin >keys/admin/eks-admin-creds

##patch aws-auth config with added iam 
#create admin user kube config
kubectl  get cm aws-auth -n kube-system -o yaml> k8s-aws-auth.yaml
cat resources/patch-aws-auth.yaml | sed -e "s@dev-arn@$DEV_ROLE_ARN@g" \
                                   | sed -e "s@test-arn@$TEST_ROLE_ARN@g" \
                                   | sed -e "s@ops-arn@$OPS_ROLE_ARN@g" \
                                   | sed -e "s@admin-arn@$ADMIN_ROLE_ARN@g" \
                                   | tee resources/patch-aws-auth.temp.yaml
sed -i '' '/mapRoles: |/r resources/patch-aws-auth.temp.yaml' k8s-aws-auth.yaml
kubectl delete cm aws-auth -n kube-system
kubectl  apply -f k8s-aws-auth.yaml

# kubectl patch cm aws-auth --patch "$(cat resources/patch-aws-auth.temp.yaml)" -n kube-system

## create kube config
export K8S_API_LB_NAME=$(aws eks describe-cluster --name $NAME  --query cluster.[endpoint] --output=text)
export CA_AUTHORITY_DATA=$(aws eks describe-cluster --name $NAME  --query cluster.[certificateAuthority.data] --output text)

#create dev user kube config
cat resources/eks-kube-config.yaml | sed -e "s@endpoint-url@$K8S_API_LB_NAME@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$DEV_ROLE_ARN@g" \
                                   | sed -e "s@common-name@dev@g" \
                                   | sed -e "s@kubernetes@dev@g" \
                                   | tee keys/dev/dev-eks-kube-config.yaml
#create test user kube config
cat resources/eks-kube-config.yaml | sed -e "s@endpoint-url@$K8S_API_LB_NAME@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$TEST_ROLE_ARN@g" \
                                   | sed -e "s@common-name@test@g" \
                                   | sed -e "s@kubernetes@test@g" \
                                   | tee keys/test/test-eks-kube-config.yaml
#create ops user kube config
cat resources/eks-kube-config.yaml | sed -e "s@endpoint-url@$K8S_API_LB_NAME@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$OPS_ROLE_ARN@g" \
                                   | sed -e "s@common-name@ops@g" \
                                   | sed -e "s@kubernetes@ops@g" \
                                   | tee keys/ops/ops-eks-kube-config.yaml
#create admin user kube config
cat resources/eks-kube-config.yaml | sed -e "s@endpoint-url@$K8S_API_LB_NAME@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$ADMIN_ROLE_ARN@g" \
                                   | sed -e "s@common-name@admin-user@g" \
                                   | sed -e "s@kubernetes@admin-user@g" \
                                   | tee keys/admin/admin-eks-kube-config.yaml
#############rbac enable##########

kubectl apply -f resources/rbac-dev.yaml
kubectl apply -f resources/rbac-test.yaml
kubectl apply -f resources/rbac-ops.yaml
kubectl apply -f resources/rbac-admin-user.yaml
kubectl apply -f resources/default-resources.yaml
kubectl apply -f resources/dev-resources.yaml
# kubectl apply -f resources/ingestor-resources.yaml
kubectl apply -f resources/prod-resources.yaml
kubectl apply -f resources/test-resources.yaml
kubectl apply -f resources/ops-resources.yaml

################################

#####rbac tests #####
#validate that all users can view resources in all namespaces

set -x
echo "should be yes "
kubectl auth can-i get pods --as test --all-namespaces
kubectl auth can-i get pods --as ops --all-namespaces
kubectl auth can-i get pods --as dev --all-namespaces
echo ""
##validate admin rights
echo "should be no "
kubectl auth can-i create pods --as  test --all-namespaces
kubectl auth can-i create pods --as  dev  --all-namespaces
kubectl auth can-i create pods --as  ops  --all-namespaces
echo ""
echo "should be yes "
kubectl auth can-i create pods --as  test -n test
kubectl auth can-i create pods --as  dev  -n dev
kubectl auth can-i create pods --as  dev  -n test
kubectl auth can-i create pods --as  ops  -n ops
kubectl auth can-i create pods --as  ops  -n test
kubectl auth can-i create pods --as  ops  -n dev
# kubectl auth can-i create pods --as  ops  -n ingestor
kubectl auth can-i create pods --as  ops  -n prod
echo ""
echo "should be no "
##validate no super user access for k8s users
#should be no
kubectl --namespace dev auth can-i \
    "*" "*" --as dev

kubectl --namespace test auth can-i \
    "*" "*" --as test

kubectl  auth can-i \
        "*" "*" --as ops --all-namespaces
echo ""
echo "should be yes "
kubectl  auth can-i \
        "*" "*" --as admin-user --all-namespaces
set +x
##########################


##--------------------
echo "
export KUBECONFIG=\$PWD/dev-eks-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/dev-eks-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
# echo \"\"
# echo \"To login to grafana use below token : it has an expiry so you will need to regenerate if its expired \"
# echo \"\"
# kubectl -n metrics \
#     get secret grafana \
#     -o jsonpath=\"{.data.admin-password}\" \
#     | base64 --decode; echo
echo \"-------------------------------\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n dev describe secret \$(kubectl -n dev get secret | grep dev-sa  | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"\"
echo \"-------------------------------------------------------\"
echo \"kubectl -n dev describe secret \$(kubectl -n dev get secret | grep dev-sa  | awk '{print \$1}') | grep token: \"
echo \"-------------------------------------------------------\""> keys/dev/set-up-dev.sh

##---------------
echo "
export KUBECONFIG=\$PWD/test-eks-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/test-eks-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
echo \"-------------------------------\"
# echo \"\"
# echo \"To login to grafana use below token : it has an expiry so you will need to regenerate if its expired \"
# echo \"\"
# kubectl -n metrics \
#     get secret grafana \
#     -o jsonpath=\"{.data.admin-password}\" \
#     | base64 --decode; echo
echo \"\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n test describe secret \$(kubectl -n test get secret | grep test-sa | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"\"
echo \"-------------------------------------------------------\"
echo \"kubectl -n test describe secret \$(kubectl -n test get secret | grep test-sa  | awk '{print \$1}') | grep token: \"
echo \"-------------------------------------------------------\"" > keys/test/set-up-test.sh

##----------
echo "
export KUBECONFIG=\$PWD/ops-eks-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/ops-eks-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
echo \"-------------------------------\"

echo \"\"
echo \"your monitoring and alerting portal uid/password :\" sysops:$BASIC_AUTH_PWD
echo \"\"

# echo \"To login to grafana use below token with admin as userid : it has an expiry so you will need to regenerate if its expired \"
# echo \"\"
# kubectl -n metrics \
#     get secret grafana \
#     -o jsonpath=\"{.data.admin-password}\" \
#     | base64 --decode; echo

echo \"\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n ops describe secret \$(kubectl -n ops get secret | grep ops-sa | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"\"
echo \"-------------------------------------------------------\"
echo \"kubectl -n ops describe secret \$(kubectl -n ops get secret | grep ops-sa | awk '{print \$1}') | grep token: \"
echo \"-------------------------------------------------------\""> keys/ops/set-up-ops.sh

##----------
echo "
export KUBECONFIG=\$PWD/admin-eks-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/admin-eks-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
echo \"-------------------------------\"

echo \"your monitoring and alerting portal uid/password :\" sysops:$BASIC_AUTH_PWD
echo \"\"

echo \"To login to grafana use below token with admin uid : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n metrics get secret grafana -o jsonpath=\"{.data.admin-password}\" | base64 --decode; echo
echo \"\"
echo \"\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n kube-system describe secret \$(kubectl -n kube-system get secret | grep admin-user-sa | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"\"
echo \"-------------------------------------------------------\"
echo \"kubectl -n kube-system describe secret \$(kubectl -n kube-system get secret | grep admin-user-sa | awk '{print \$1}') | grep token: \"
echo \"-------------------------------------------------------\""> keys/admin/set-up-admin.sh

##----------------

####copy read me #####

cp README.md keys/test/README.md
cp README.md keys/dev/README.md
cp README.md keys/ops/README.md
cp README.md keys/admin/README.md

##########


####zip folders ####

zip -r keys/ops keys/ops
zip -r keys/test keys/test
zip -r keys/dev keys/dev
zip -r keys/admin keys/admin

####################



