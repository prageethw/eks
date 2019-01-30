source ./chaos_monkey.temp
echo "wait... chaos monkey unistalling ..."
aws iam detach-role-policy --role-name aws-chaos-monkey --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam delete-role --role-name aws-chaos-monkey
aws lambda delete-function --function-name chaosLambda
rm -rf chaos_*
