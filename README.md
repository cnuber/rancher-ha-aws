# RKE and Rancher HA on AWS

This project provides terraform and some scripts to easily stand up AWS resources and infrastructure, deploy an RKE Kubernetes cluster and the Rancher management server in HA.

### Prerequisites

- rke version 0.2.5 or newer [RKE Download](https://rancher.com/docs/rke/latest/en/installation/#download-the-rke-binary) 
- helm version 2.12.1 or newer [helm client download](https://github.com/helm/helm/releases)
- kubectl version 0.13.3 or newer [kubectl client download](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- terraform 0.12.x [terraform client download](https://www.terraform.io/downloads.html)
- an AWS profile with sufficient access to deploy the necessary resources
- a VPC to deploy to at AWS
- at least *3* subnets associated with the VPC

### Configuring deployment settings

The terraform.tfvars file in this repository contains the settings that need to be configured before running the terraform.  Each var has a comment describing what is needed.  Aside from modifying these variables, you may wish to lock down the ssh and load balancer security group rules to trusted addresses.  This will be variablized in upcoming releases.

If deploying Rancher with the "private" SSL setting you will need tot ensure that you copy your SSL certificate, key and ca into the root directory before running the terraform.  The files need to be named specifically as follows for Rancher to read the secrets created:

```
tls.crt  
tls.key  
cacerts.pem  
```

(This will be updated to take a path in upcoming releases)

### Creating the S3 storage bucket 

export CLUSTER_NAME=mycluster # set this to the desired cluster name (must be consistent everywhere)

cd state_stores # switch to the state storage directory

cp terraform.tfvars.example $CLUSTER_NAME.tfvars  # copy the example var file to one for this cluster

vim $CLUSTER_NAME.tfvars # set the values to the desired values

terraform init

terraform plan -var-file=$CLUSTER_NAME.tfvars

terraform apply -var-file=$CLUSTER_NAME.tfvars

### Running the terraform to build the cluster

# create and populate a tfvars file for the cluster 

export CLUSTER_NAME=mycluster # set this to the desired cluster name (must be consistent everywhere)

cp terraform.tfvars.example tfvars/$CLUSTER_NAME.tfvars # copy the example tfvars to one for this cluster

vim tfvars/$CLUSTER_NAME.tfvars # modify the vars for your cluster deployment

# Initialize terraform with the proper backend configuration for your cluster name

terraform init -backend-config=state_stores/backends/backend-$CLUSTER_NAME.conf -var-file=tfvars/$CLUSTER_NAME.tfvars

# Run a plan to ensure desired output

terraform plan -var-file=tfvars/$CLUSTER_NAME.tfvars

# Run apply to deploy the cluster

terraform apply -var-file=tfvars/$CLUSTER_NAME.tfvars

# *** Be sure to copy the locally generated file in rke/kube_config_$CLUSTER_NAME-cluster.yml to somewhere secure as this is the admin Kubernetes configuration for the server should Rancher and other auth become unavailable!

## Authors

* **Chris Nuber**

