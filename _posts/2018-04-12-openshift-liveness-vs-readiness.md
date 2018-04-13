---
layout: post
title: Openshift Liveness probes vs Readiness probes
categories: [Openshift, health, probes, liveness, readiness]
tags: [cloud, openshift, apps, probes, readiness, liveness]
description: Short example of main difference between liveness and readiness probes
fullview: false
---

I had this discussion few times already, where people confuse liveness and readiness probes. There is few more difference between `liveness` and `readiness` probes. But one of the main difference is that failed `readiness` probe removes pod from the pool, but DO NOT RESTART. On the other hand failed `liveness` probe removes pod from the pool and RESTARTS the pod.

Lets show this as an example. Simple pod which has 2 probes, set of files.

```
apiVersion: v1
kind: Pod
metadata:
  labels:
    test: liveness-vs-readiness
  name: liveness-vs-readiness-exec
spec:
  containers:
  - name: liveness
    image: k8s.gcr.io/busybox
    args:
    - /bin/sh
    - -c
    - touch /tmp/healthy; touch /tmp/liveness; sleep 999999
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/liveness
      initialDelaySeconds: 5
      periodSeconds: 5
    readinessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 5
```

Lets create this pod and show this in action: `oc create -f liveness-vs-readiness.yaml`


Output of pod status while we do actions inside the pod. Number in front of the name coresponds to the actions done inside the pod:
```
[root@default ~]# oc get pods -w
NAME                         READY     STATUS    RESTARTS   AGE
[1] liveness-vs-readiness-exec   1/1       Running   0         44s
[2] liveness-vs-readiness-exec   0/1       Running   0         1m
[3] liveness-vs-readiness-exec   1/1       Running   0         2m
[4] liveness-vs-readiness-exec   0/1       Running   1         3m
    liveness-vs-readiness-exec   1/1       Running   1         3m
```

Actions inside the container: 
```
[root@default ~]# oc rsh liveness-vs-readiness-exec 
# [1] we rsh to the pod and do nothing. Pod is healthy and live
# [2] we remove health probe file and see that pod goes to notReady state
# rm /tmp/healthy 
# 
# [3] we create health file again and see that pod goes to ready state without restart
# touch /tmp/healthy
# 
# [4] we remove liveness file and check that pods goes to notready state and is restart just after that
# rm /tmp/liveness 
# command terminated with exit code 137
```

Here you go :)