#! /bin/bash

# disable selinux
setenforce 0 &

# stop local firewall
systemctl stop firewalld &

# start elasticsearch
systemctl start elasticsearch

# wait for elasticsearch to start
until [ $(curl -s -o /dev/null -w '%{http_code}' -u elastic:temppass localhost:9200) -eq 200 > /dev/null 2>&1 ]; do sleep 1; done

# set built-in user passwords
curl -u elastic:temppass -X PUT -H 'Content-Type: application/json' http://localhost:9200/_xpack/security/user/elastic/_password -d '{"password":"elastic_acg"}'
curl -u elastic:elastic_acg -X PUT -H 'Content-Type: application/json' http://localhost:9200/_xpack/security/user/kibana_system/_password -d '{"password":"kibana_acg"}'
curl -u elastic:elastic_acg -X PUT -H 'Content-Type: application/json' http://localhost:9200/_xpack/security/user/beats_system/_password -d '{"password":"beats_acg"}'

# wait for other elasticsearch nodes to start
until [ $(curl -s -o /dev/null -w '%{http_code}' -u elastic:elastic_acg 10.0.1.102:9200) -eq 200 > /dev/null 2>&1 ]; do sleep 1; done;
until [ $(curl -s -o /dev/null -w '%{http_code}' -u elastic:elastic_acg 10.0.1.103:9200) -eq 200 > /dev/null 2>&1 ]; do sleep 1; done;

# start kibana
systemctl start kibana &

# load filebeat ingest pipelines
filebeat modules enable system
filebeat setup

# load metricbeat ingest pipelines
metricbeat setup

# start beats
systemctl start filebeat metricbeat &

# wait for kibana to start
until [ $(curl -s -o /dev/null -w '%{http_code}' -u elastic:elastic_acg localhost/status) -eq 200 > /dev/null 2>&1 ]; do sleep 1; done;

# enable kibana dark mode and set default route to the console
curl -u elastic:elastic_acg -X POST -H "Content-type: application/json" -H 'kbn-xsrf: true' localhost/api/kibana/settings -d '{"changes":{"theme:darkMode":true,"defaultRoute":"/app/dev_tools#/console"}}' &

# load and break the shakespeare dataset
wget https://github.com/ACloudGuru/content-elastic-certified-engineer/raw/master/shakespeare.zip
unzip shakespeare.zip

curl -u elastic:elastic_acg localhost:9200/shakespeare -XPUT -H 'Content-Type: application/json' -d '{"settings": {"number_of_shards": 3,"number_of_replicas": 2, "index.routing.allocation.exclude._name": "node-3"}}'
curl -u elastic:elastic_acg -H 'Content-Type: application/x-ndjson' -XPOST 'localhost:9200/shakespeare/_bulk?pretty' --data-binary @shakespeare.json > /dev/null 2>&1
curl -u elastic:elastic_acg -H 'Content-Type: application/x-ndjson' -XPOST 'localhost:9200/shakespeare/_refresh'

# load and break the accounts dataset
wget https://github.com/ACloudGuru/content-elastic-certified-engineer/raw/master/accounts.zip
unzip accounts.zip
curl -u elastic:elastic_acg localhost:9200/accounts -XPUT -H 'Content-Type: application/json' -d '{"settings":{"number_of_shards": 3, "number_of_replicas": 0}}'
curl -u elastic:elastic_acg -H 'Content-Type: application/x-ndjson' -XPOST 'localhost:9200/accounts/_bulk?pretty' --data-binary @accounts.json > /dev/null 2>&1
curl -u elastic:elastic_acg -H 'Content-Type: application/x-ndjson' -XPOST 'localhost:9200/accounts/_refresh'

# Break the metricbeat index
curl -u elastic:elastic_acg localhost:9200/metricbeat-7.13.4/_settings -XPUT -H 'Content-Type: application/json' -d '{"number_of_replicas": 3}'