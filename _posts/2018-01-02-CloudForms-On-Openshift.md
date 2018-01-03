---
layout: post
title: CloudForms deployment on Openshift
categories: [Openshift, Cloud, CloudForms]
tags: [cloud, containers monitoring, new relic, openshift]
description: How to deploy and configure CloudForms on Openshift
fullview: false
---

This guide will help you to deploy [CloudForms](https://www.redhat.com/en/technologies/management/cloudforms) containerized version into Openshift and configure it to track our Openshift deployment.

Pre-requisites for this guide are working Openshift cluster with enough capacity to run CloudForms and [hawkular](https://docs.openshift.com/container-platform/3.6/install_config/cluster_metrics.html) deployed.

<b>Note</b>: CloudForms in the current state is not fit for the active Openshift environment monitoring. But it makes a great tool for capacity and compliance management

Our deployment steps are from [Installing Red Hat CloudForms on Openshift Container Platform user guide](https://access.redhat.com/documentation/en-us/red_hat_cloudforms/4.5/html/installing_red_hat_cloudforms_on_openshift_container_platform/)

Our development cluster configuration on AWS is:

```
1 Master
1 Infra Node
3 GlusterFS nodes
3 Workers

master_instance_type = "t2.medium"
node_instance_type = "t2.large"
```

Setup is done using my personal development scripts from [openshift-ansible-wrapper project](https://github.com/mjudeikis/openshift-ansible-wrapper)

#### Cloudforms deployment

Create the project, ServiceAccount role bindings, and template for CloudForms.

```
oc new-project cloudforms
oc adm policy add-scc-to-user anyuid system:serviceaccount:cloudforms:cfme-anyuid
oc adm policy add-scc-to-user privileged system:serviceaccount:cloudforms:default
oc create -f  https://raw.githubusercontent.com/openshift/openshift-ansible/master/roles/openshift_examples/files/examples/v1.5/cfme-templates/cfme-template.yaml

#to check what parameters you can configure change:
oc process --parameters -n cloud-forms cloudforms


NAME                                 DESCRIPTION                                                                                                 GENERATOR           VALUE
NAME                                 The name assigned to all of the frontend objects defined in this template.                                                      cloudforms
DATABASE_SERVICE_NAME                The name of the OpenShift Service exposed for the PostgreSQL container.                                                         postgresql
DATABASE_USER                        PostgreSQL user that will access the database.                                                                                  root
DATABASE_PASSWORD                    Password for the PostgreSQL user.                                                                           expression          [a-zA-Z0-9]{8}
DATABASE_NAME                        Name of the PostgreSQL database accessed.                                                                                       vmdb_production
DATABASE_REGION                      Database region that will be used for application.                                                                              0
MEMCACHED_SERVICE_NAME               The name of the OpenShift Service exposed for the Memcached container.                                                          memcached
MEMCACHED_MAX_MEMORY                 Memcached maximum memory for memcached object storage in MB.                                                                    64
MEMCACHED_MAX_CONNECTIONS            Memcached maximum number of connections allowed.                                                                                1024
MEMCACHED_SLAB_PAGE_SIZE             Memcached size of each slab page.                                                                                               1m
POSTGRESQL_MAX_CONNECTIONS           PostgreSQL maximum number of database connections allowed.                                                                      100
POSTGRESQL_SHARED_BUFFERS            Amount of memory dedicated for PostgreSQL shared memory buffers.                                                                256MB
APPLICATION_CPU_REQ                  Minimum amount of CPU time the Application container will need (expressed in millicores).                                       1000m
POSTGRESQL_CPU_REQ                   Minimum amount of CPU time the PostgreSQL container will need (expressed in millicores).                                        500m
MEMCACHED_CPU_REQ                    Minimum amount of CPU time the Memcached container will need (expressed in millicores).                                         200m
APPLICATION_MEM_REQ                  Minimum amount of memory the Application container will need.                                                                   6144Mi
POSTGRESQL_MEM_REQ                   Minimum amount of memory the PostgreSQL container will need.                                                                    1024Mi
MEMCACHED_MEM_REQ                    Minimum amount of memory the Memcached container will need.                                                                     64Mi
APPLICATION_MEM_LIMIT                Maximum amount of memory the Application container can consume.                                                                 16384Mi
POSTGRESQL_MEM_LIMIT                 Maximum amount of memory the PostgreSQL container can consume.                                                                  8192Mi
MEMCACHED_MEM_LIMIT                  Maximum amount of memory the Memcached container can consume.                                                                   256Mi
POSTGRESQL_IMG_NAME                  This is the PostgreSQL image name requested to deploy.                                                                          registry.access.redhat.com/cloudforms45/cfme-openshift-postgresql
POSTGRESQL_IMG_TAG                   This is the PostgreSQL image tag/version requested to deploy.                                                                   latest
MEMCACHED_IMG_NAME                   This is the Memcached image name requested to deploy.                                                                           registry.access.redhat.com/cloudforms45/cfme-openshift-memcached
MEMCACHED_IMG_TAG                    This is the Memcached image tag/version requested to deploy.                                                                    latest
APPLICATION_IMG_NAME                 This is the Application image name requested to deploy.                                                                         registry.access.redhat.com/cloudforms45/cfme-openshift-app
APPLICATION_IMG_TAG                  This is the Application image tag/version requested to deploy.                                                                  latest
APPLICATION_DOMAIN                   The exposed hostname that will route to the application service, if left blank a value will be defaulted.                       
APPLICATION_INIT_DELAY               Delay in seconds before we attempt to initialize the application.                                                               15
APPLICATION_VOLUME_CAPACITY          Volume space available for application data.                                                                                    5Gi
APPLICATION_REGION_VOLUME_CAPACITY   Volume space available for region application data.                                                                             5Gi
DATABASE_VOLUME_CAPACITY             Volume space available for database.                                                                                            15Gi
```

For CloudForms datastore backend we will be using glusterFS with  StorageClasses. When our template initiates PersistantVolumeClaim, it will be fulfilled by our GlusterFS deployment. If you don't have StorageClasses enabled as default, you need to pre-create PersistanceVolume pool.

Deploy CloudForms in our environment:

```
oc new-app --template=cloudforms -p POSTGRESQL_MEM_LIMIT=1Gi -p DATABASE_VOLUME_CAPACITY=2Gi -p APPLICATION_MEM_LIMIT=3.5Gi -p APPLICATION_MEM_REQ=2Gi
```

<b>Note</b>: our limits are set much lower than recommended ones. This is our development cluster and we don't have sufficient capacity. Refer to (deployment manual) for recommended capacity.

If everything went well you should have CF deployed and running. Because current release (4.5) do not log to `stdout` you will not see any logs in `webUI` or `oc logs` command. To check logs execute:

```
#Logs into the container
oc rsh cloudforms-0
#tail log files
tail -f /persistent/server-data/var/www/miq/vmdb/log/*
```

---- 
<b>Optional:</b>

If `admin/smartvm` username and password do not work, we need to reset password hard way :) Follow "How To" in [Access.redhat.com portal](https://access.redhat.com/solutions/801103).

```
oc rsh cloudforms-0
cd /var/www/miq/vmdb
source /root/.bash_profile 
rails r "User.find_by_userid('admin').update_attributes(:password => 'new_password')" 
```
---


#### Cloudforms configuration

When CF is deployed we need to configure it to track our Openshift cluster.

First, we link Metrics project (`openshift-infra`) with CloudForms project (`cloudforms`). 

```
oc adm pod-network join-projects --to=cloudforms openshift-infra
```

After this, we can use Service Discovery when configuring CloudForms.

Main provider configuration guidelines can be found in [access.redhat.com portal](https://access.redhat.com/solutions/2137531).

First get `managment-admin` token for metrics:
`oc sa get-token management-admin -n management-infra`

![picture]({{ "/assets/media/cloudforms/2017-12-29 12-17-48.png" | absolute_url }})

Configure master and Hawkular endpoints with token to access API's in provider sections:
```
kubernetes.default.svc.cluster.local
hawkular-metrics.openshift-infra.svc.cluster.local
```

![picture]({{ "/assets/media/cloudforms/2017-12-28 12-13-27.png" | absolute_url }})

![picture]({{ "/assets/media/cloudforms/2017-12-28 12-13-40.png" | absolute_url }})

![picture]({{ "/assets/media/cloudforms/2017-12-28 12-50-48.png" | absolute_url }})

![picture]({{ "/assets/media/cloudforms/2017-12-28 12-55-30.png" | absolute_url }})

Configure data collection in CF settings. 

![picture]({{ "/assets/media/cloudforms/2017-12-29 12-20-46.png" | absolute_url }})

![picture]({{ "/assets/media/cloudforms/2017-12-29 12-22-53.png" | absolute_url }})

If everything was done right you should start seeing metrics after 10-15 minutes. 

![picture]({{ "/assets/media/cloudforms/2017-12-29 12-38-30.png" | absolute_url }})
