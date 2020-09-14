# delete istio
kubectl delete -f istio-install-demo-profile.yaml
str="label \"istio-injection\" not found."
for each in $(kubectl get ns -o jsonpath="{.items[*].metadata.name}" );
do
  val=$(kubectl label namespace $each istio-injection- | head -1)
  if [ "$val" != "$str" ]; then
    echo $each
    kubectl rollout restart all --namespace=$each
  fi
done
