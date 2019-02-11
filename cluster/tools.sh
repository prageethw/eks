#!/bin/bash
helm repo update
#install ingress
# helm install stable/nginx-ingress --name nginx-ingress --namespace nginx-ingress \
#             --set controller.service.enableHttp=true \
#             --set controller.stats.enabled=true \
#             --set controller.metrics.enabled=true \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-proxy-protocol"=* \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-backend-protocol"=http \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-connection-idle-timeout"=3600 \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"=$AWS_SSL_CERT_ARN \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-ports"=https
# kubectl -n nginx-ingress  rollout status deployment nginx-ingress-controller

# install auto nodes scaler
helm install stable/cluster-autoscaler \
    --name aws-cluster-autoscaler \
    --namespace aws-cluster-autoscaler \
    --version 0.11.0 \
    --set autoDiscovery.clusterName=$NAME \
    --set awsRegion=$AWS_DEFAULT_REGION \
    --set sslCertPath=/etc/kubernetes/pki/ca.crt \
    --set rbac.create=true \
    --set autoscalingGroupsnamePrefix[0].maxSize=10 \
    --set autoscalingGroupsnamePrefix[0].minSize=2 \
    --set autoscalingGroupsnamePrefix[0].name=$NAME \
    --set extraArgs.scale-down-delay-after-add="5m0s" \
    --set extraArgs.scale-down-unneeded-time="5m0s" \
    --set extraArgs.scale-down-unready-time="10m0s" \
    --set extraArgs.scale-down-utilization-threshold=0.8 \
    --set extraArgs.scan-interval="20s" \
    --set extraArgs.skip-nodes-with-system-pods=0 \
    --set extraArgs.skip-nodes-with-local-storage=0 \
    --set extraArgs.balance-similar-node-groups="true" \
    --set replicaCount=2 \
    --set podDisruptionBudget="minAvailable: 1" \
    --set resources.limits.cpu="200m",resources.limits.memory="100Mi"
kubectl -n aws-cluster-autoscaler rollout status deployment aws-cluster-autoscaler
# kubectl apply -f resources/aws-ca-pdb.yaml

# install external-dns statful service no replicas supported atm
helm install stable/external-dns --namespace external-dns --name external-dns --version=1.3.0 \
        --set aws.secretKey=$AWS_SECRET_ACCESS_KEY \
        --set aws.accessKey=$AWS_ACCESS_KEY_ID \
        --set aws.region=$AWS_DEFAULT_REGION \
        --set rbac.create=true \
        --set txtPrefix=kops- \
        --set policy=sync \
        --set txtOwnerId=kops \
        --set sources={ingress} \
        --set resources.limits.cpu="200m",resources.limits.memory="100Mi" 
kubectl -n external-dns rollout status deployment external-dns
kubectl apply -f resources/external-dns-pdb.yaml
kubectl apply -f resources/external-dns-hpa.yaml

#install dashboard  for k8s cluster needs to run in kube-system
helm install stable/kubernetes-dashboard --name kubernetes-dashboard --namespace kube-system --version=0.10.2 \
                     --set ingress.enabled=true \
                     --set ingress.hosts[0]=$DASHBOARD_ADDR \
                     --set service.externalPort=8080 \
                     --set service.internalPort=8080 \
                     --set enableInsecureLogin=true \
                     --set replicaCount=2 
kubectl -n kube-system rollout status deployment kubernetes-dashboard
kubectl apply -f resources/kube-dashboard-pdb.yaml

# install metrics server runs on all nodes
helm install stable/metrics-server \
    --name metrics-server \
    --version 2.3.0 \
    --set replicas=2 \
    --namespace metrics \
    --set resources.limits.cpu="100m",resources.limits.memory="50Mi"
#--kubelet-preferred-address-types=InternalIP\,Hostname\,ExternalIP
kubectl -n metrics rollout status deployment metrics-server
kubectl apply -f resources/metrics-server-hpa.yaml
kubectl apply -f resources/metrics-server-pdb.yaml

# install monitoring and alerting tools
# enable basic auth
htpasswd -c -b  ./keys/auth sysops $BASIC_AUTH_PWD
kubectl create secret generic sysops --from-file ./keys/auth -n metrics
helm install stable/prometheus \
    --name prometheus \
    --namespace metrics \
    --version 8.4.3 \
    --set server.ingress.hosts={$PROM_ADDR} \
    --set alertmanager.ingress.hosts={$AM_ADDR} \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-type"=basic \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-secret"=sysops \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-realm"="Authentication Required - ok" \
    --set server.statefulSet.enabled="true" \
    --set server.resources.limits.cpu="500m",server.resources.limits.memory="4Gi" \
    --set server.resources.requests.cpu="250m",server.resources.requests.memory="2Gi" \
    --set alertmanager.resources.limits.cpu="200m",server.resources.limits.memory="1Gi" \
    --set alertmanager.resources.requests.cpu="100m",server.resources.requests.memory="0.5Gi" \
    --set alertmanager.statefulSet.enabled="true" \
    -f resources/monitoring-alerting-limits.yml
kubectl -n metrics rollout status deployment prometheus-kube-state-metrics
kubectl -n metrics rollout status statefulset prometheus-alertmanager
kubectl -n metrics rollout status statefulset prometheus-server
kubectl apply -f resources/prometheus-pdb.yaml

#validate basic auth with
# curl -v -u sysops:$BASIC_AUTH_PWD https://$PROM_ADDR

#install prom adaptor for prom integration with k8s metrics server
helm install \
    stable/prometheus-adapter \
    --name prometheus-adapter \
    --version v0.3.0 \
    --namespace metrics \
    --set rbac.create=true \
    --set image.tag=v0.3.0 \
    --set metricsRelistInterval=90s \
    --set prometheus.url=http://prometheus-server.metrics.svc \
    --set prometheus.port=80 \
    --set resources.limits.cpu="100m",resources.limits.memory="100Mi" \
    --values resources/prom-adapter-values.yml
kubectl -n metrics rollout status deployment prometheus-adapter

# install grafana
helm install stable/grafana \
    --name grafana \
    --namespace metrics \
    --version 1.24.1 \
    --set replicas=1 \
    --set ingress.hosts="{$GRAFANA_ADDR}" \
    --set server.resources.limits.cpu="200m",server.resources.limits.memory="500Mi" \
    --values resources/grafana-values.yml
kubectl -n metrics rollout status deployment grafana
kubectl  apply -f resources/grafana-pdb.yaml