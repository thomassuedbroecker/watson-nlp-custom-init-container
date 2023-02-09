# Create a model container image for `Watson NLP for Embed`

This project shows how to :

* ... **create** a model [_init container_](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) with a custom model for [`Watson NLP for Embed`](https://www.ibm.com/docs/en/watson-libraries?topic=watson-natural-language-processing-library-embed-home).
* ... **upload** the `model init container` to the [IBM Cloud Container Registry](https://www.ibm.com/cloud/container-registry).
* ... **deploy** the `model init container` and the `Watson NLP runtime` to an [IBM Cloud Kubernetes Cluster](https://www.ibm.com/cloud/kubernetes-service).
* ... **test** `Watson NLP runtime` with the loaded model using the `REST API`.

Therefor the project reuses information from the IBM Developer tutorial [_`Serve a custom model on a Kubernetes or Red Hat OpenShift cluster`_](https://developer.ibm.com/tutorials/serve-custom-models-on-kubernetes-or-openshift/).

> Please visit the blog post [How to create a model container image for Watson NLP for Embed](https://wp.me/paelj4-1PM) for the documentation of the project.

