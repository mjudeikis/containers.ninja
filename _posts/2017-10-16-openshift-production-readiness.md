---
layout: post
title: Openshift Production Readiness Check-list
categories: [Openshift, Cloud, Planning, Strategy]
tags: [cloud, openshift, production, realiness]
fullview: false
comments: false
---

Following [Enterprise Deployment](https://containers.ninja/openshift/deployment/planning/2017/08/15/enterprise-deployment.html) list I wanted to conver some other end of the spectrum. Productionalizing your service. Following good pratices we tried to collect check-list, which you need to implement, know so you could consider yourself - production ready. 

List is collated from experiance, leassons learned, and wider literature around this subject.

1. Platform Stability
    Do you have standart development cycle? Each change to the platfom "machinery" is going via standartize (not yet automated but preferably yes) process? Just lets not overengineer here. We still should be able to deploy multiple times a day, so process "Review deployment weekly" is not the best example.

2. Testing
    Does any custom code you deliver (pre, post  requisites, changes) is tested? Do you have stagging environment which is SAME as your production environment. Do you do stess testing? Again, not overengineer. You dont need to blow a Datacentre away each time you do a release or DR test.

    Do you have smoke tests in place? Fake deploymnets checking different platform functionality. In example service discovery, S2I builds, registries integration, etc.

3. Pipelines and delta
    How you differenciate your development, production deployment. 

4. Dependencies
    Do you know all platform dependencies and key people to contanct? Storage, networks, even your customer dependencies - Databases, caching, etc.

5. Monitoring
    Do you know how your platform performance changes after updates, patches? How memory, CPU footprint changed? How you do know how your application behaving? Can you notice memory leacks on the platform level?

    Can you spot your hardware failures using alers? 

6. Capacity
    Can you scale you capacity on demand? What is lead time to provision new hardware and scale? How it impact your platform performance and onboarding?

7. Be ready for the worst
    Platform should not have single point of failure. If it does, you need know know it and know how to recover from it. It can be lose of infrastrucure, lose in capacity, or external dependencies failures.

    Do you know how to cope with failures, caused by traffic increase, or malicious acitivity. Do you know how to limit trafic based on region, origin, patterns?

8. Logging
    Can you easily access logs from the platform? Can you map alerts with logs fast? Does alerting and logging is integrated together?

9. On-call
    Do you have defined process for oncall and does on-call person know what to do?

10. Documentation
    Do you have documenation on whats running in your estate? Is it easily accessible? Up to date? Do you know

