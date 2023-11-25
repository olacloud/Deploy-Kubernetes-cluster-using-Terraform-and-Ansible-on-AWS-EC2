# Deploy a Kubernetes cluster using Terraform and Ansible on AWS EC2

To begin with the setup we use terraform to create the necessary infrastructure on AWS and dynamically create an ansible inventory file populated with the IP Addresses of the instances.\
After the infrastructure is created, we use Ansible to create the 1.28 cluster, including the control and worker nodes. \
The first instance will be the control node ( set as "master" in generated inventory) while the remaining instances will be worker nodes (set as worker-x).\
Ansible will generate the Kubeadm join command on the control node and enter the command in the worker nodes to join the cluster.

Prerequisites
------------
+ Install terraform
+ Install ansible
+ Create the  Key-pair in aws and name it as server
+ Create .aws directory in your home directory and create a credentials file with the following details in it (If you don't have AWS CLI installed on your machine)

```
[default]
aws_access_key_id = "[ACCESS KEY]"
aws_secret_access_key = "[SECRET ACCESS KEY]"
region = "eu-west-2"

$ terraform init
$ terraform plan
$ terraform apply
```

Terraform will deploy the vpc, subnet, security group, networking and EC2 instances and output an inventory.yaml file for ansible to use to bootstrap the kubernetes using an ansible role.

Clone the ansible role from https://github.com/olacloud/install-kubernetes-ubuntu/ and cd into the directory. Copy the generated inventory file to the directory and run

$ ansible-playbook -i inventory.yaml install-kubernetes.yaml 
