#!/bin/bash
helm repo update
# install ingress
# helm install  stable/nginx-ingress --name nginx-ingress --namespace nginx-ingress \
#             --version 1.36.0 \
#             --set controller.publishService.enabled=true \
#             --set controller.service.targetPorts.https=http \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-proxy-protocol"=* \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-backend-protocol"=http \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-connection-idle-timeout"=3600 \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"=$AWS_SSL_CERT_ARN \
#             --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-ports"=https \
#             --set-string controller.config.ssl-redirect=true \
#             --set-string controller.config.use-forwarded-headers=true \
#             --set-string controller.config.use-proxy-protocol=false \
#             --set-string controller.config.force-ssl-redirect=true \
#             --set-string controller.config.hsts=true
# kubectl -n nginx-ingress  rollout status deployment nginx-ingress-controller

# install auto nodes scaler
helm install stable/cluster-autoscaler \
    --name aws-cluster-autoscaler \
    --namespace aws-cluster-autoscaler \
    --version 7.0.0 \
    --set autoDiscovery.clusterName=$NAME \
    --set awsRegion=$AWS_DEFAULT_REGION \
    --set sslCertPath=/etc/kubernetes/pki/ca.crt \
    --set rbac.create=true \
    --set extraArgs.scale-down-delay-after-add="5m0s" \
    --set extraArgs.scale-down-unneeded-time="5m0s" \
    --set extraArgs.scale-down-unready-time="10m0s" \
    --set extraArgs.scale-down-utilization-threshold=0.6 \
    --set extraArgs.scan-interval="20s" \
    --set extraArgs.balance-similar-node-groups="true" \
    --set extraArgs.skip-nodes-with-system-pods="false" \
    --set extraArgs.skip-nodes-with-local-storage="false" \
    --set extraArgs.expander="least-waste" \
    --set replicaCount=2 \
    --set podDisruptionBudget="minAvailable: 1" \
    --set resources.limits.cpu="100m",resources.limits.memory="200Mi"
kubectl -n aws-cluster-autoscaler rollout status deployment aws-cluster-autoscaler
# kubectl apply -f resources/aws-ca-pdb.yaml

# install external-dns statful service no replicas supported atm
# if you enable istio as below you need to intall istio-ingressgateway crds to make it work else an error thrown.
helm install bitnami/external-dns --namespace external-dns --name external-dns --version=3.2.3 \
        --set aws.credentials.secretKey=$AWS_SECRET_ACCESS_KEY \
        --set aws.credentials.accessKey=$AWS_ACCESS_KEY_ID \
        --set aws.region=$AWS_DEFAULT_REGION \
        --set rbac.create=true \
        --set txtPrefix=kops- \
        --set policy=sync \
        --set txtOwnerId=kops \
        --set sources="{ingress,istio-gateway}" \
        --set resources.limits.cpu="100m",resources.limits.memory="200Mi"
kubectl -n external-dns rollout status deployment external-dns
kubectl apply -f resources/external-dns-pdb.yaml
kubectl apply -f resources/external-dns-hpa.yaml

# install dashboard  for k8s cluster needs to run in kube-system
helm install kubernetes-dashboard/kubernetes-dashboard --name kubernetes-dashboard --namespace kube-system --version=2.2.0 \
                     --set ingress.enabled=true \
                     --set ingress.hosts[0]=$DASHBOARD_ADDR \
                     --set service.externalPort=8080 \
                     --set service.internalPort=8080 \
                     --set resources.limits.cpu="200m",alertmanager.resources.limits.memory="100Mi" \
                     --set enableInsecureLogin=true \
                     --set replicaCount=2
kubectl -n kube-system rollout status deployment kubernetes-dashboard
kubectl apply -f resources/kube-dashboard-pdb.yaml

# install metrics server runs on all nodes
helm install stable/metrics-server \
    --name metrics-server \
    --version 2.11.1 \
    --set replicas=2 \
    --namespace metrics \
    --set args={"--kubelet-insecure-tls=true,--kubelet-preferred-address-types=InternalIP\,Hostname\,ExternalIP"} \
    --set resources.limits.cpu="50m",resources.limits.memory="100Mi"
# --kubelet-preferred-address-types=InternalIP\,Hostname\,ExternalIP
kubectl -n metrics rollout status deployment metrics-server
kubectl apply -f resources/metrics-server-hpa.yaml
kubectl apply -f resources/metrics-server-pdb.yaml

# enable basic auth
htpasswd -c -b  ./keys/auth sysops $BASIC_AUTH_PWD
kubectl create secret generic sysops --from-file ./keys/auth -n metrics

# install monitoring and alerting tools
# leave this as 1 replicas to make stats valid as much as it could.
helm install stable/prometheus \
    --name prometheus \
    --namespace metrics \
    --version 11.7.0 \
    --set server.ingress.hosts={$PROM_ADDR} \
    --set alertmanager.ingress.hosts={$AM_ADDR} \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-type"=basic \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-secret"=sysops \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-realm"="Authentication Required - ok" \
    --set server.statefulSet.enabled="true" \
    --set server.resources.limits.cpu="1000m",server.resources.limits.memory="2Gi" \
    --set server.resources.requests.cpu="500m",server.resources.requests.memory="1Gi" \
    --set alertmanager.resources.limits.cpu="500m",alertmanager.resources.limits.memory="1Gi" \
    --set alertmanager.resources.requests.cpu="250m",alertmanager.resources.requests.memory="0.5Gi" \
    --set nodeExporter.resources.limits.cpu="200m",alertmanager.resources.limits.memory="0.6Gi" \
    --set nodeExporter.resources.requests.cpu="100m",alertmanager.resources.requests.memory="0.5Gi" \
    --set alertmanager.statefulSet.enabled="true" \
    -f resources/monitoring-alerting-limits.yml
kubectl -n metrics rollout status deployment prometheus-kube-state-metrics
kubectl -n metrics rollout status statefulset prometheus-alertmanager
kubectl -n metrics rollout status statefulset prometheus-server
kubectl apply -f resources/prometheus-pdb.yaml

# validate basic auth with
# curl -v -u sysops:$BASIC_AUTH_PWD https://$PROM_ADDR

# install prom adaptor for prom integration with k8s metrics server, note pointing to istio prom.
# helm install \
#     stable/prometheus-adapter \
#     --name prometheus-adapter \
#     --version 2.0.0 \
#     --namespace metrics \
#     --set logLevel=4 \
#     --set rbac.create=true \
#     --set image.tag=v0.5.0 \
#     --set metricsRelistInterval=90s \
#     --set prometheus.url=http://prometheus.istio-system.svc \
#     --set prometheus.port=9090 \
#     --set resources.limits.cpu="150m",resources.limits.memory="300Mi" \
#     --values resources/prom-adapter-values.yml
#     # --set prometheus.url=http://prometheus-server.metrics.svc --set prometheus.port=80
# kubectl -n metrics rollout status deployment prometheus-adapter
# kubectl apply -f resources/prom-adapter-hpa.yaml
# kubectl apply -f resources/prom-adapter-pdb.yaml

# install grafana
helm install stable/grafana \
    --name grafana \
    --namespace metrics \
    --version 5.3.5 \
    --set persistence.type="statefulset" \
    --set persistence.size="5Gi" \
    --set podDisruptionBudget.minAvailable=1 \
    --set ingress.hosts="{$GRAFANA_ADDR}" \
    --set server.resources.limits.cpu="200m",server.resources.limits.memory="1000Mi" \
    --values resources/grafana-values.yml
kubectl -n metrics rollout status statefulset grafana
kubectl  apply -f resources/grafana-pdb.yaml

# kube-metrics adapter is a general purpose prom adaptor seems less complicated than prometheus-adapter
# Note: this chart is not from official repo
helm install \
    banzaicloud-stable/kube-metrics-adapter \
    --name kube-metrics-adapter \
    --version 0.0.5 \
    --namespace metrics \
    --set logLevel=1 \
    --set rbac.create=true \
    --set aws.enable=true \
    --set prometheus.url=http://prometheus.istio-system.svc:9090 \
    --set resources.limits.cpu="150m",resources.limits.memory="300Mi"\
    --set image.repository=registry.opensource.zalan.do/teapot/kube-metrics-adapter \
    --set image.tag=v0.1.5
kubectl -n metrics rollout status deployment kube-metrics-adapter
kubectl apply -f resources/kube-metrics-adapter-hpa.yaml
kubectl apply -f resources/kube-metrics-adapter-pdb.yaml

# install flagger
helm upgrade -i flagger flagger-stable/flagger \
    --version 1.0.0 \
    --namespace=metrics \
    --set crd.create=true \
    --set meshProvider=istio \
    --set metricsServer=http://prometheus.istio-system:9090
kubectl -n metrics rollout status deployment flagger
kubectl apply -f resources/flagger-hpa.yaml
kubectl apply -f resources/flagger-pdb.yaml