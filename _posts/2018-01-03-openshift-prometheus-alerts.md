---
layout: post
title: Prometheus alerts on Openshift
categories: [Openshift, Cloud, Prometheus, Monitoring, Grafana]
tags: [cloud, containers monitoring, openshift, prometheus, grafana, snmp]
description: How to Configure Prometheus, Grafana, and Openshift to send alerts when triggered
fullview: false
---

Prometheus is one of the fastest [Cloud Native Computing Foundation](https://www.cncf.io/blog/2017/06/28/survey-shows-kubernetes-leading-orchestration-platform/) projects being adopted. And now it comes as a native product into OpenShift stack. It gives everything that good enterprise monitoring tool need in one place: Good API, easy integration, time series database, real time data, alerting, and flexibility. And having good visibility of your cluster state is one of the most important things about operating distributed system. 

In this guide, we will configure [Openshift Prometheus](https://github.com/openshift/prometheus) to send email alerts. In addition, we will configure [Grafana](https://grafana.com/) dashboard to show some basic metrics. All components--Prometheus, NodeExporter, and Grafana--will be created in the separate projects. Prometheus web UI and AlertManager UI will be used only for configuration and testing. Our OpenShift cluster already has Prometheus deployed using [Ansible Playbooks](https://github.com/openshift/openshift-ansible/tree/master/playbooks/openshift-prometheus).
Ansible Playbook will create 1 pod with 6 containers running. This will change in the future when the HA solution for Prometheus and AlertManager is developed. But for now, this will do :)

We will deploy `node-exporter` so we can have some node level metrics too.

```
oc adm new-project openshift-metrics-node-exporter --node-selector='zone=az1'
oc project openshift-metrics-node-exporter
oc create -f https://raw.githubusercontent.com/openshift/origin/master/examples/prometheus/node-exporter.yaml -n openshift-metrics-node-exporter
oc adm policy add-scc-to-user -z prometheus-node-exporter -n openshift-metrics-node-exporter hostaccess
```

To deploy Grafana we will use an already existing project from [mrsiano](https://github.com/mrsiano) [github](https://github.com/mrsiano/grafana-ocp) project. 

```
git clone https://github.com/mrsiano/grafana-ocp
cd grafana-ocp
./setup-grafana.sh prometheus-ocp openshift-metrics true
```

To configure Grafana to consume Prometheus, we will link `grafana` and `openshift-metrics` projects:

```
oc adm pod-network join-projects --to=grafana openshift-metrics
```

For the authentication read `management-admin` service account token:

```
oc sa get-token management-admin -n management-infra
```

Login to Grafana dashboard and add new source:

```
https://prometheus.openshift-metrics.svc.cluster.local
```

![picture]({{ "/assets/media/prometheus/2018-01-03 17-10-23.png" | absolute_url }})

Example queries were taken from [OpensShift Git repository](https://github.com/openshift/origin/tree/master/examples/prometheus))

For cluster memory: `sum(container_memory_rss) / sum(machine_memory_bytes)`

For changes in the cluster: `sum(changes(container_start_time_seconds[10m]))`

For API calls: `sum(apiserver_request_count{verb=~"POST|PUT|DELETE|PATCH"}[5m])` and `sum(apiserver_request_count{verb=~"GET|LIST|WATCH"}[5m])`

![picture]({{ "/assets/media/prometheus/2018-01-03 17-28-32.png" | absolute_url }})

Next, we will configure the alerts and mail client. For mail messages, I will use [mailjet.com](https://app.mailjet.com) as it gives an easy way to send mail via SMTP.

Now the alert manager is not exposed to outside world, so we will expose it temporarily, in order to see alerts being generated.

```
cat <<EOF | oc create -n openshift-metrics -f -
apiVersion: v1
kind: Service
metadata:
 labels:
   name: alertmanager
 name: alertmanager
 namespace: openshift-metrics
spec:
 ports:
 - port: 8080
   protocol: TCP
   targetPort: 9093
 selector:
   app: prometheus
 sessionAffinity: None
 type: ClusterIP
status:
 loadBalancer: {}
EOF
 
oc expose service alertmanager -n openshift-metrics
route="$(oc get routes -n openshift-metrics alertmanager --template='{{ .spec.host }}')"
echo "Try accessing $route"
```

We need to modify Prometheus configMap to enable our new rules for alerts. We execute `oc edit cm prometheus` and add this:
```
prometheus.rules: |
   groups:
   - name: example-rules
     interval: 30s # defaults to global interval
     rules:
     - alert: "Node Down"
       expr: up{job="kubernetes-nodes"} == 0
       annotations:
         miqTarget: "ContainerNode"
         severity: "ERROR"
         url: "https://www.example.com/node_down_fixing_instructions"
         message: "Node {{$labels.instance}} is down"
     - alert: "Too Many Pods"
       expr: sum(kubelet_running_pod_count) > 15
       annotations:
         miqTarget: "ExtManagementSystem"  
         severity: "ERROR"
         url: "https://www.example.com/too_many_pods_fixing_instructions"
         message: "Too many running pods"
     - alert: "Node CPU Usage"
       expr: (100 - (avg by (instance) (irate(node_cpu{app="prometheus-node-exporter",mode="idle"}[5m])) * 100)) > 3
       for: 30s
       labels:
         severity: "ERROR"
       annotations:
         miqTarget: "ExtManagementSystem"
         severity: "ERROR"
         url: "https://www.example.com/too_many_pods_fixing_instructions"
         message: "{{$labels.instance}}: CPU usage is above 4% (current value is: {{ $value }})"
```

This will create an alert on running pods count, CPU usage, and if the node is down.

We can check the same data in the Prometheus web UI:`(100 - (avg by (instance) (irate(node_cpu{app="prometheus-node-exporter",mode="idle"}[5m])) * 100)) > 4` and `sum(kubelet_running_pod_count)`

Now we will configure our mail client for the alert manager.
Edit configMap `oc edit cm prometheus-alerts` and modify it to look like this:

```
apiVersion: v1
data:
 alertmanager.yml: |
   global:
     smtp_smarthost: 'in-v3.mailjet.com:25'
     smtp_from: 'xxxx@gmail.com'
     smtp_auth_username: 'xxxxx'
     smtp_auth_password: 'xxxxx'
   # The root route on which each incoming alert enters.
   route:
     # default route if none match
     receiver: all

     # The labels by which incoming alerts are grouped together. For example,
     # multiple alerts coming in for cluster=A and alertname=LatencyHigh would
     # be batched into a single group.
     # TODO:
     group_by: []

     # All the above attributes are inherited by all child routes and can
     # overwritten on each.

   receivers:
   - name: alert-buffer-wh
     webhook_configs:
     - url: http://localhost:9099/topics/alerts
   - name: mail
     email_configs:
     - to: "info@containers.ninja"
   - name: all
     email_configs:
     - to: "info@containers.ninja"
     webhook_configs:
     - url: http://localhost:9099/topics/alerts
kind: ConfigMap
metadata:
 creationTimestamp: null
 name: prometheus-alerts
```

This will send alert to both backends, so they will be available via API of the `alert-buffer` and `mail`.

alert buffer api `https://alerts-openshift-metrics.apps.34.229.160.53.xip.io/topics/alerts` shows alerts being triggered:
![picture]({{ "/assets/media/prometheus/2018-01-04 13-39-21.png" | absolute_url }})

And after few seconds emails start coming through:
![picture]({{ "/assets/media/prometheus/2018-01-04 14-29-41.png" | absolute_url }})

It is early stage for Prometheus in Openshift. But even with current configuration the value it brings to the platform is huge. Having real time monitoring with close to real time alerts is the key to the success when operating distributed system. If this didn’t convinced you yet about importance of real time alerting, more arguments can be found in the [Alerting from Time-Series Data](https://landing.google.com/sre/book/chapters/practical-alerting.html) blog post from our friends at Google. 