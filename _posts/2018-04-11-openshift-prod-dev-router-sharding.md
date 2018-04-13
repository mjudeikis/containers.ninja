---
layout: post
title: Openshift Router Sharding for Production and Development traffic
categories: [Openshift, Loadbalancing, HAProxy, Sharding]
tags: [cloud, openshift, haproxy, ha, sharding, high-availability]
description: How to configure Openshift HAProxy router to split production and development traffic for different projects using labels
fullview: false
---

The bigger Openshift cluster you are running, more you need to think about your workloads economy. Most organizations start with separate clusters for development and production workloads. Usually, the reasoning being a separation of duties and different SLA requirements.

But at some point organization might reach certain technological maturity when it starts making sense to run Production and Development workloads on the same server. This allows to increase density, save on computing power by utilizing Quality of Service [QoS](https://blog.openshift.com/managing-compute-resources-openshiftkubernetes/) and scheduler capabilities. 

If you are already there, you potentially already thought about logical separation of your production and development components. Here we will speak about traffic separation.

If your developers are doing a benchmark and load testing on a development application, it would not impact your production traffic.

For this reason, we will use router sharding and we will create separate routers for different purposes.

This is our cluster high level architecture:

![alt text]({{ "/assets/media/routersharding/sharding.png" | absolute_url }})

In this cluster, we do not dedicate nodes from different workloads. We just split traffic.

Our Global Loadbalancer is running haproxy, and contains configuration:
```
acl host_router_dev req.ssl_sni -m sub -i apps-dev.example.com
acl host_router_prod req.ssl_sni -m sub -i apps-prod.example.com

use_backend atomic-openshift-router-dev if host_router_dev
use_backend atomic-openshift-router-prod if host_router_prod
```
Full configuration: https://gist.github.com/mjudeikis/0a1ae3f9c5f18a39f8d1dc107c31a872 

We route different sub-domains to different routers.

On Openshift side we deploy 3 routers: 2 for Production and 1 for Development workloads:

```
oc adm router router-prod --replicas=2 --force-subdomain='${name}-${namespace}.apps-prod.example.com'
oc adm router router-dev --replicas=1 --force-subdomain='${name}-${namespace}.apps-dev.example.com' 
```

we use `--force-subdomain` to force separate subdomains for separate routers. You can mix those configurations to suit your use-case.

Next we will dedicate routers to serve traffic only subset of namespaces:
```
oc set env dc/router-prod NAMESPACE_LABELS="router=prod"
oc set env dc/router-dev NAMESPACE_LABELS="router=dev"
```

We make sure that our routers are running on their dedicated nodes:
```
oc label node infra1.example.com "router=prod" 
oc label node infra2.example.com "router=prod"
oc label node infra3.example.com "router=dev"

#patch deployments of the router:
oc patch dc router-dev -p "spec:
  template:
    spec:
      nodeSelector:
        router: dev"

oc patch dc router-prod -p "spec:
  template:
    spec:
      nodeSelector:
        router: prod"
```

After this we need to make sure that project dedicated to different workloads would have an appropriate label on them:

```
oc new-project prod
oc label namespace prod router=prod
```

And lets test our configuration:
```
oc new-app cakephp-mysql-example

#in our case we updated routes to be https, because we care :)
[root@console-REPL ~]# oc get route
NAME                    HOST/PORT                                                   PATH      SERVICES                PORT      TERMINATION   WILDCARD
cakephp-mysql-example   cakephp-mysql-example-prod.apps-prod.example.com            cakephp-mysql-example   web       edge          None
```

We see taht route already contains `apps-prod` subdomain for production workloads. Test same on 

Repeat same for development project:
```
oc new-project dev
oc label namespace dev router=dev  
oc new-app cakephp-mysql-example
[root@console-REPL ~]# oc get route
NAME                    HOST/PORT                                                 PATH      SERVICES                PORT      TERMINATION   WILDCARD
cakephp-mysql-example   cakephp-mysql-example-dev.apps-dev.example.com           cakephp-mysql-example   web       edge          None
```

Test both url:
```
[root@console-REPL ~]# curl -sSLk -D - https://cakephp-mysql-example-dev.apps-dev.example.com -o /dev/null 
HTTP/1.1 200 OK
Date: Wed, 11 Apr 2018 13:27:54 GMT
Server: Apache/2.4.27 (Red Hat) OpenSSL/1.0.1e-fips
Content-Length: 64467
Content-Type: text/html; charset=UTF-8
Set-Cookie: 1b15022d32bdaf178e4bb662559c535f=9b517482994c000cd2b19fe8ca6174e2; path=/; HttpOnly; Secure
Cache-control: private

[root@console-REPL ~]# curl -sSLk -D - https://cakephp-mysql-example-prod.apps-prod.example.com -o /dev/null 
HTTP/1.1 200 OK
Date: Wed, 11 Apr 2018 13:28:46 GMT
Server: Apache/2.4.27 (Red Hat) OpenSSL/1.0.1e-fips
Content-Length: 64484
Content-Type: text/html; charset=UTF-8
Set-Cookie: 2e2307f4645f03dde968155c002d6b44=8316f5abdc2526e8edcb1b110e430325; path=/; HttpOnly; Secure
Cache-control: private
```
By splitting traffic we make sure we can meet our application SLA's and at the same time manage less clusters. By having everything in one cluster, we can save on hardware, people resources and maintenance costs. But before you jump towards "one cluster architecture", ask yourself - are you ready for this?

This blog post is simplified version of [openshift router documentation](https://docs.openshift.com/container-platform/3.9/install_config/router/default_haproxy_router.html)

Special thanks for help to [@noeloc](https://twitter.com/noeloc)