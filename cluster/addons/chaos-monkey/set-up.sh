CHAOS_MONKEY_ARN=$(aws iam create-role --role-name aws-chaos-monkey --assume-role-policy-document file://assume-chaos-monkey-iam-role-policy.json | jq -r .Role.Arn)
aws iam attach-role-policy --role-name aws-chaos-monkey --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
echo "wait ... chaos monkey set-up ..."
sleep 10
chaos-lambda deploy -r $CHAOS_MONKEY_ARN
echo "export CHAOS_MONKEY_ARN=$CHAOS_MONKEY_ARN">chaos_monkey.temp
