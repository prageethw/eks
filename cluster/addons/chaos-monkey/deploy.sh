source ../../k8s-eks-cluster.temp
IFS=, read ng1 ng2 ng3 <<< "$ASG_NAMES"
ASG_NAMES="\"$ng1\"","\"$ng2\"","\"$ng3"\"
cat Chaosfile.json  | sed -e  "s@\"NODE_ASGS\"@$ASG_NAMES@g" | tee chaos_file.temp.json
echo "wait till chaos monkey deployed ... "
chaos-lambda deploy -c chaos_file.temp.json