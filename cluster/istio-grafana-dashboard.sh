# Address of Grafana
GRAFANA_HOST="https://$GRAFANA_ADDR"
# Login credentials, if authentication is used
PASSWORD="$(kubectl -n metrics get secret grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo)"
GRAFANA_CRED="admin:$PASSWORD"
# The name of the Prometheus data source to use
GRAFANA_DATASOURCE="Prometheus"
# The version of Istio to deploy
ISTIO_CONTROL_PLANE="$(istioctl version --remote | grep "control plane version")"
VERSION=${ISTIO_CONTROL_PLANE#*:}
# Import all Istio dashboards
for DASHBOARD in 7639 11829 7636 7630 7642 7645; do
    REVISION="$(curl -s https://grafana.com/api/dashboards/${DASHBOARD}/revisions -s | jq ".items[] | select(.description | contains(\"${VERSION}\")) | .revision")"
    echo $REVISION
    curl -s https://grafana.com/api/dashboards/${DASHBOARD}/revisions/${REVISION}/download > dashboard-$DASHBOARD.json
    echo "Importing $(cat dashboard-$DASHBOARD.json | jq -r '.title') (revision ${REVISION}, id ${DASHBOARD})..."
    curl -s -k -u "$GRAFANA_CRED" -XPOST \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"dashboard\":$(cat dashboard-$DASHBOARD.json),\"overwrite\":true, \
            \"inputs\":[{\"name\":\"DS_PROMETHEUS\",\"type\":\"datasource\", \
            \"pluginId\":\"prometheus\",\"value\":\"$GRAFANA_DATASOURCE\"}]}" \
        $GRAFANA_HOST/api/dashboards/import
    echo -e "\nDone\n"
    rm dashboard-*.json
done
