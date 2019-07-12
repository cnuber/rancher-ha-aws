# RKE and Rancher HA on AWS

This project provides terraform and some scripts to easily stand up AWS resources and infrastructure, deploy an RKE Kubernetes cluster and the Rancher management server in HA.

### Prerequisites

```
rke
helm
kubectl
terraform 0.12.x
an AWS profile with sufficient access to deploy the necessary resources
```

### Configuring deployment settings

```
The terraform.tfvars file in this repository contains the settings that need to be configured before running the terraform.  Each var has a comment describing what is needed.  Aside from modifying these variables, you may wish to lock down the ssh and load balancer security group rules to trusted addresses.  This will be variablized in upcoming releases.
```
If deploying Rancher with the "private" SSL setting you will need tot ensure that you copy your SSL certificate, key and ca into the root directory before running the terraform.  The files need to be named specifically as follows for Rancher to read the secrets created:

tls.crt
tls.key
cacerts.pem

(This will be updated to take a path in upcoming releases)
```
```
### Running the terraform

Always run plan before applying any Terraform and review the output to ensure it's going to do what is intended!

terraform plan

Once you've reviewed the plan output you can then run the apply:

terraform apply

If all goes well you should have a fully functional HA Rancher Management server atop an HA Kubernetes Cluster on AWS EC2 instances!

## Authors

* **Chris Nuber**

