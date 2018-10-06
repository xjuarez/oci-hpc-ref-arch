#!/bin/bash

SERVER=$1
cd /root/oci-hpc-ref-arch/scripts/
curl -u admin:admin -X POST http://localhost:3000/api/datasources/ \
-H "Content-Type: application/json" \
-d '{"name":"ganglia2","type":"grafana-simple-json-datasource","url":"http://$SERVER:9000","access":"Server","basicAuth":false}'

curl -u admin:admin -X POST http://localhost:3000/api/dashboards/db/ \
-H "Content-Type: application/json" \
-d "@grafana_dashboard.in"