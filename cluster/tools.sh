#!/bin/bash
helm repo update
# install ingress
# kubectl create namespace nginx-ingress
# helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx --namespace nginx-ingress \
#             --version 3.3.0 \
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

# install cluster auto scaler
kubectl create namespace aws-cluster-autoscaler
helm upgrade -i aws-cluster-autoscaler autoscaler/cluster-autoscaler-chart \
    --namespace aws-cluster-autoscaler \
    --version 1.0.3 \
    --set autoDiscovery.clusterName=$NAME \
    --set awsRegion=$AWS_DEFAULT_REGION \
    --set sslCertPath=/etc/kubernetes/pki/ca.crt \
    --set rbac.create=true \
    --set autoscalingGroupsnamePrefix[0].maxSize=10 \
    --set autoscalingGroupsnamePrefix[0].minSize=2 \
    --set autoscalingGroupsnamePrefix[0].name=$ASG_NAME \
    --set extraArgs.scale-down-delay-after-add="5m0s" \
    --set extraArgs.scale-down-unneeded-time="5m0s" \
    --set extraArgs.scale-down-unready-time="10m0s" \
    --set extraArgs.scale-down-utilization-threshold=0.75 \
    --set extraArgs.scan-interval="20s" \
    --set extraArgs.balance-similar-node-groups="true" \
    --set extraArgs.skip-nodes-with-system-pods="false" \
    --set extraArgs.skip-nodes-with-local-storage="false" \
    --set extraArgs.expander="least-waste" \
    --set replicaCount=2 \
    --set podDisruptionBudget.maxUnavailable=1 \
    --set resources.limits.cpu="100m",resources.limits.memory="400Mi" \
    --set resources.requests.cpu="50m",resources.requests.memory="60Mi"
kubectl -n aws-cluster-autoscaler rollout status deployment aws-cluster-autoscaler-aws-cluster-autoscaler-chart
# kubectl apply -f resources/aws-ca-pdb.yaml

# install external-dns statful service no replicas supported atm
# if you enable istio as below you need to intall istio-ingressgateway crds to make it work else an error thrown.
kubectl create namespace external-dns
helm upgrade -i external-dns  bitnami/external-dns --namespace external-dns --version=3.2.3 \
        --set aws.credentials.secretKey=$AWS_SECRET_ACCESS_KEY \
        --set aws.credentials.accessKey=$AWS_ACCESS_KEY_ID \
        --set aws.region=$AWS_DEFAULT_REGION \
        --set rbac.create=true \
        --set txtPrefix=kops- \
        --set policy=sync \
        --set txtOwnerId=kops \
        --set sources="{ingress,istio-gateway}" \
        --set resources.limits.cpu="50m",resources.limits.memory="100Mi" \
        --set resources.requests.cpu="25m",resources.requests.memory="50Mi"
kubectl -n external-dns rollout status deployment external-dns
kubectl apply -f resources/external-dns-pdb.yaml
kubectl apply -f resources/external-dns-hpa.yaml

# install dashboard  for k8s cluster needs to run in kube-system
helm upgrade -i kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --namespace kube-system --version=2.2.0 \
                     --set ingress.enabled=true \
                     --set ingress.hosts[0]=$DASHBOARD_ADDR \
                     --set service.externalPort=8080 \
                     --set service.internalPort=8080 \
                     --set resources.limits.cpu="100m",alertmanager.resources.limits.memory="100Mi" \
                     --set resources.requests.cpu="50m",alertmanager.resources.requests.memory="100Mi" \
                     --set enableInsecureLogin=true \
                     --set replicaCount=2
kubectl -n kube-system rollout status deployment kubernetes-dashboard
kubectl apply -f resources/kube-dashboard-pdb.yaml

# install metrics server runs on all nodes
kubectl create namespace metrics
helm upgrade -i metrics-server stable/metrics-server \
    --version 2.11.2 \
    --set replicas=2 \
    --namespace metrics \
    --set args={"--kubelet-insecure-tls=true,--kubelet-preferred-address-types=InternalIP\,Hostname\,ExternalIP"} \
    --set resources.limits.cpu="50m",resources.limits.memory="100Mi" \
    --set resources.requests.cpu="20m",resources.requests.memory="50Mi"
# --kubelet-preferred-address-types=InternalIP\,Hostname\,ExternalIP
kubectl -n metrics rollout status deployment metrics-server
kubectl apply -f resources/metrics-server-hpa.yaml
kubectl apply -f resources/metrics-server-pdb.yaml

# enable basic auth
htpasswd -c -b  ./keys/auth sysops $BASIC_AUTH_PWD
kubectl create secret generic sysops --from-file ./keys/auth -n metrics

# install monitoring and alerting tools
# leave this as 1 replicas to make stats valid as much as it could.
helm upgrade -i prometheus prometheus/prometheus \
    --namespace metrics \
    --version 11.15.0 \
    --set server.ingress.hosts={$PROM_ADDR} \
    --set alertmanager.ingress.hosts={$AM_ADDR} \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-type"=basic \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-secret"=sysops \
    --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/auth-realm"="Authentication Required - ok" \
    --set server.statefulSet.enabled="true" \
    --set server.global.scrape_interval="15s" \
    --set server.resources.limits.cpu="1000m",server.resources.limits.memory="2.5Gi" \
    --set server.resources.requests.cpu="500m",server.resources.requests.memory="1.8Gi" \
    --set alertmanager.resources.limits.cpu="50m",alertmanager.resources.limits.memory="100Mi" \
    --set alertmanager.resources.requests.cpu="25m",alertmanager.resources.requests.memory="50Mi" \
    --set nodeExporter.resources.limits.cpu="50m",nodeExporter.resources.limits.memory="100Mi" \
    --set nodeExporter.resources.requests.cpu="20m",nodeExporter.resources.requests.memory="30Mi" \
    --set pushgateway.resources.limits.cpu="25m",pushgateway.resources.limits.memory="50Mi" \
    --set pushgateway.resources.requests.cpu="10m",pushgateway.resources.requests.memory="25Mi" \
    --set kube-state-metrics.resources.requests.cpu="25m",kube-state-metrics.resources.requests.memory="50Mi" \
    --set kube-state-metrics.resources.limits.cpu="50m",kube-state-metrics.resources.limits.memory="100Mi" \
    --set alertmanager.statefulSet.enabled="true" \
    -f resources/monitoring-alerting-limits.yml
kubectl -n metrics rollout status deployment prometheus-kube-state-metrics
kubectl -n metrics rollout status statefulset prometheus-alertmanager
kubectl -n metrics rollout status statefulset prometheus-server
kubectl apply -f resources/prometheus-pdb.yaml

# validate basic auth with
# curl -v -u sysops:$BASIC_AUTH_PWD https://$PROM_ADDR

# install prom adaptor for prom integration with k8s metrics server, note pointing to istio prom.
# helm upgrade -i prometheus-adapter \
#     prometheus/prometheus-adapter \
#     --version 2.7.0 \
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
helm upgrade -i grafana grafana/grafana \
    --namespace metrics \
    --version 5.6.9 \
    --set persistence.type="statefulset" \
    --set persistence.size="5Gi" \
    --set podDisruptionBudget.minAvailable=1 \
    --set ingress.hosts="{$GRAFANA_ADDR}" \
    --set resources.limits.cpu="100m",resources.limits.memory="150Mi" \
    --set resources.requests.cpu="50m",resources.requests.memory="60Mi" \
    --values resources/grafana-values.yml
kubectl -n metrics rollout status statefulset grafana
kubectl  apply -f resources/grafana-pdb.yaml

# kube-metrics adapter is a general purpose prom adaptor seems less complicated than prometheus-adapter
# Note: this chart is not from official repo 
helm upgrade -i kube-metrics-adapter \
    banzaicloud-stable/kube-metrics-adapter \
    --version 0.1.3 \
    --namespace metrics \
    --set enableCustomMetricsApi=true \
    --set enableExternalMetricsApi=true \
    --set logLevel=1 \
    --set rbac.create=true \
    --set aws.enable=true \
    --set prometheus.url=http://prometheus-server.metrics:80 \
    --set resources.limits.cpu="50m",resources.limits.memory="150Mi"\
    --set resources.requests.cpu="25m",resources.requests.memory="60Mi"\
    --set image.repository=registry.opensource.zalan.do/teapot/kube-metrics-adapter \
    --set image.tag=v0.1.5
kubectl apply -f resources/kube-metrics-rbac-fix.yaml # this can be removed once fixes are merged.
kubectl -n metrics rollout status deployment kube-metrics-adapter
kubectl apply -f resources/kube-metrics-adapter-hpa.yaml
kubectl apply -f resources/kube-metrics-adapter-pdb.yaml

# install flagger
helm upgrade -i flagger flagger-stable/flagger \
    --version 1.1.0 \
    --namespace metrics \
    --set meshProvider=istio \
    --set resources.limits.cpu=25m \
    --set resources.limits.memory=60Mi \
    --set resources.requests.cpu=10m \
    --set resources.requests.memory=40Mi \
    --set metricsServer=http://prometheus-server.metrics:80
kubectl -n metrics rollout status deployment flagger
kubectl apply -f resources/flagger-hpa.yaml
kubectl apply -f resources/flagger-pdb.yaml

# intall kiali-operator
helm upgrade -i kiali-operator kiali/kiali-operator \
    --version 1.27.0 \
    --namespace istio-system \
    --set debug.enabled=true \
    --set cr.create=false \
    --set watchNamespace=istio-system \
    --set resources.limits.cpu=100m \
    --set resources.limits.memory=200Mi \
    --set resources.requests.cpu=50m \
    --set resources.requests.memory=100Mi 
kubectl apply -f resources/kiali-cr.yaml -n istio-system #install kiali

#install jaeger via operator,not prod ready if you want prod ready use helm as below with ES saas.
helm upgrade -i jaeger-operator jaeger/jaeger-operator \
    --namespace istio-system \
    --set resources.limits.cpu=50m \
    --set resources.limits.memory=100Mi \
    --set resources.requests.cpu=25m \
    --set resources.requests.memory=50Mi
kubectl apply -f resources/jaeger-cr.yaml -n istio-system #install jaeger

# # install jaeger refer doc to point external database
# helm upgrade -i jaeger jaeger/jaeger \
#     --version 0.37.2 \
#     --namespace istio-system \
#     --set schema.resources.limits.cpu=100m \
#     --set schema.resources.limits.memory=200Mi \
#     --set agent.resources.limits.cpu=100m \
#     --set agent.resources.limits.memory=200Mi \
#     --set collector.resources.limits.cpu=500m \
#     --set collector.resources.limits.memory=512Mi \
#     --set collector.service.zipkin.port=9411 \
#     --set query.resources.limits.cpu=500m \
#     --set query.resources.limits.memory=512Mi \
#     --set cassandra.config.max_heap_size=1024M \
#     --set cassandra.config.heap_new_size=256M \
#     --set cassandra.resources.requests.memory=2048Mi \
#     --set cassandra.resources.requests.cpu=0.4 \
#     --set cassandra.resources.limits.memory=2048Mi \
#     --set cassandra.resources.limits.cpu=0.4 \
#     --set schema.extraEnv[0].name=MODE,schema.extraEnv[0].value=prod #prod will run 3 cassendra instances