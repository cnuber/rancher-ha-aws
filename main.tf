terraform {
  required_version = "~> 0.12"

  backend "s3" {
  }
}
provider "aws" {
  profile = "${var.aws_profile}"
  region  = "${var.aws_region}"
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "${var.cluster_name}-rke"
  public_key = "${file(var.ssh_public_key_file)}"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # official Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_subnet_ids" "available" {
  vpc_id = "${var.rancher_vpc_id}"
}

resource "aws_security_group" "rancher-elb" {
  name   = "${var.cluster_name}-rancher-elb"
  vpc_id = "${var.rancher_vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_security_group" "rancher" {
  name   = "${var.cluster_name}-rancher-server"
  vpc_id = "${var.rancher_vpc_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = ["${aws_security_group.rancher-elb.id}"]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "TCP"
    security_groups = ["${aws_security_group.rancher-elb.id}"]
  }

  # etcd communication
  ingress {
    from_port       = 2379
    to_port         = 2380
    protocol        = "TCP"
    cidr_blocks     = ["${var.rancher_vpc_cidr}"]
  }
  # K8s kube-api for kubectl
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # K8s NodePorts
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Open intra-cluster
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks  = ["${var.rancher_vpc_cidr}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "template_file" "cloud_config" {
  template = <<EOF
  #cloud-config
  repo_update: true
  repo_upgrade: all
  
  runcmd:
   - [ sh, -c, "curl -sL https://releases.rancher.com/install-docker/${var.docker_version}.sh | sh" ]
   - [ sh, -c, "usermod -aG docker ${var.ssh_username}" ]
EOF
}

resource "aws_instance" "rancher_etcd_node" {
  count         = "${var.rancher_etcd_node_count}"
  ami           = "${data.aws_ami.ubuntu.image_id}"
  instance_type = "${var.server_instance_type}"
  key_name      = "${aws_key_pair.ssh_key.id}"
  user_data     = "${data.template_file.cloud_config.rendered}"

  vpc_security_group_ids      = ["${aws_security_group.rancher.id}"]
  subnet_id                   = "${tolist(data.aws_subnet_ids.available.ids)[count.index]}"
  associate_public_ip_address = true

  iam_instance_profile = "${aws_iam_instance_profile.control_plane_instance_profile.name}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "50"
  }
  tags = {
    "Name" = "${var.cluster_name}-server-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_instance" "rancher_control_plane" {
  count         = "${var.rancher_control_plane_node_count}"
  ami           = "${data.aws_ami.ubuntu.image_id}"
  instance_type = "${var.server_instance_type}"
  key_name      = "${aws_key_pair.ssh_key.id}"
  user_data     = "${data.template_file.cloud_config.rendered}"

  vpc_security_group_ids      = ["${aws_security_group.rancher.id}"]
  subnet_id                   = "${tolist(data.aws_subnet_ids.available.ids)[count.index]}"
  associate_public_ip_address = true

  iam_instance_profile = "${aws_iam_instance_profile.control_plane_instance_profile.name}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "50"
  }
  tags = {
    "Name" = "${var.cluster_name}-control-plane-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_instance" "rancher_worker" {
  count         = "${var.rancher_worker_node_count}"
  ami           = "${data.aws_ami.ubuntu.image_id}"
  instance_type = "${var.worker_instance_type}"
  key_name      = "${aws_key_pair.ssh_key.id}"
  user_data     = "${data.template_file.cloud_config.rendered}"

  vpc_security_group_ids      = ["${aws_security_group.rancher.id}"]
  subnet_id                   = "${tolist(data.aws_subnet_ids.available.ids)[count.index]}"
  associate_public_ip_address = true

  iam_instance_profile = "${aws_iam_instance_profile.worker_node_instance_profile.name}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "50"
  }
  tags = {
    "Name" = "${var.cluster_name}-worker-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_elb" "rancher" {
  name            = "${var.cluster_name}"
  subnets         = "${tolist(data.aws_subnet_ids.available.ids)}"
  security_groups = ["${aws_security_group.rancher-elb.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 2
    target              = "tcp:80"
    interval            = 5
  }

  instances    = "${aws_instance.rancher_control_plane.*.id}"
  idle_timeout = 1800

  tags = {
    Name = "${var.cluster_name}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_elb_attachment" "control_plane_elb_attach" {
        count    = "${var.rancher_control_plane_node_count}"
	elb      = "${aws_elb.rancher.id}"
	instance = "${element(aws_instance.rancher_control_plane.*.id, count.index)}"
}

resource "aws_elb_attachment" "rancher_etcd_node_elb_attach" {
        count    = "${var.rancher_etcd_node_count}"
        elb      = "${aws_elb.rancher.id}"
        instance = "${element(aws_instance.rancher_etcd_node.*.id, count.index)}"
}

resource "aws_elb_attachment" "worker_node_elb_attach" {
        count    = "${var.rancher_worker_node_count}"
        elb      = "${aws_elb.rancher.id}"
        instance = "${element(aws_instance.rancher_worker.*.id, count.index)}"
}

data "aws_route53_zone" "dns_zone" {
  name = "${var.domain_name}"
}

# DNS
resource "aws_route53_record" "rancher" {
  zone_id = "${data.aws_route53_zone.dns_zone.zone_id}"
  name    = "${var.dns_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.rancher.dns_name}"
    zone_id                = "${aws_elb.rancher.zone_id}"
    evaluate_target_health = true
  }
}

data "template_file" "rkeClusterConfig" {
  template = <<EOF
  cluster_name: "${var.cluster_name}"
  kubernetes_version: "${var.kubernetes_version}"
  cloud_provider:
    name: aws
  services:
    etcd:
      backup_config:
        interval_hours: 12
        retention: 6
        bucket_name: "rancher-${var.cluster_name}-backups"
        region: "${var.aws_region}"
        endpoint: s3.amazonaws.com
  nodes:
    - address: "${aws_instance.rancher_control_plane[0].public_ip}"
      user: "${var.ssh_username}"
      role:
        - controlplane
      internal_address: "${aws_instance.rancher_control_plane[0].private_ip}"
    - address: "${aws_instance.rancher_control_plane[1].public_ip}"
      user: "${var.ssh_username}"
      role:
        - controlplane
      internal_address: "${aws_instance.rancher_control_plane[1].private_ip}"
    - address: "${aws_instance.rancher_control_plane[2].public_ip}"
      user: "${var.ssh_username}"
      role:
        - controlplane
      internal_address: "${aws_instance.rancher_control_plane[2].private_ip}"
    - address: "${aws_instance.rancher_etcd_node[0].public_ip}"
      user: "${var.ssh_username}"
      role:
        - etcd
      internal_address: "${aws_instance.rancher_etcd_node[0].private_ip}"
    - address: "${aws_instance.rancher_etcd_node[1].public_ip}"
      user: "${var.ssh_username}"
      role:
        - etcd
      internal_address: "${aws_instance.rancher_etcd_node[1].private_ip}"
    - address: "${aws_instance.rancher_etcd_node[2].public_ip}"
      user: "${var.ssh_username}"
      role:
        - etcd
      internal_address: "${aws_instance.rancher_etcd_node[2].private_ip}"
    - address: "${aws_instance.rancher_worker[0].public_ip}"
      user: "${var.ssh_username}"
      role:
        - worker
      internal_address: "${aws_instance.rancher_worker[0].private_ip}"
    - address: "${aws_instance.rancher_worker[1].public_ip}"
      user: "${var.ssh_username}"
      role:
        - worker
      internal_address: "${aws_instance.rancher_worker[1].private_ip}"
    - address: "${aws_instance.rancher_worker[2].public_ip}"
      user: "${var.ssh_username}"
      role:
        - worker
      internal_address: "${aws_instance.rancher_worker[2].private_ip}"
  addons: |-
    ---
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: standard
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
    provisioner: kubernetes.io/aws-ebs
    parameters:
      type: gp2
EOF
}

resource "local_file" "rkeClusterConfig" {
    content     = "${data.template_file.rkeClusterConfig.rendered}"
    filename = "${path.module}/rke/${var.cluster_name}-cluster.yml"
}

resource "null_resource" "control_plane_subnet_tags" {
  count = "${var.rancher_control_plane_node_count}"
  provisioner "local-exec" {
    command = "aws --region ${var.aws_region} --profile ${var.aws_profile} ec2 create-tags --resources ${aws_instance.rancher_control_plane[count.index].subnet_id} --tags Key=\"kubernetes.io/cluster/${var.cluster_name}\",Value=\"shared\""
  }
}

resource "null_resource" "etcd_node_subnet_tags" {
  count = "${var.rancher_etcd_node_count}"
  provisioner "local-exec" {
    command = "aws --region ${var.aws_region} --profile ${var.aws_profile} ec2 create-tags --resources ${aws_instance.rancher_etcd_node[count.index].subnet_id} --tags Key=\"kubernetes.io/cluster/${var.cluster_name}\",Value=\"shared\""
  }
}

resource "null_resource" "worker_node_subnet_tags" {
  count = "${var.rancher_worker_node_count}"
  provisioner "local-exec" {
    command = "aws --region ${var.aws_region} --profile ${var.aws_profile} ec2 create-tags --resources ${aws_instance.rancher_worker[count.index].subnet_id} --tags Key=\"kubernetes.io/cluster/${var.cluster_name}\",Value=\"shared\""
  }
}

resource "null_resource" "rke_deploy" {

  provisioner "local-exec" {
    command = "sleep 300"
  }

  provisioner "local-exec" {
    command = "rke up --config ${path.module}/rke/${var.cluster_name}-cluster.yml"
  }
  provisioner "local-exec" {
    command = "${path.module}/scripts/deploy-rancher-ha.sh"
    environment = {
      KUBECONFIG = "${path.module}/rke/kube_config_${var.cluster_name}-cluster.yml"
      RANCHER_REPO="${var.rancher_version}"
      RANCHER_HOSTNAME="${var.dns_name}"
      SSL="${var.rancher_ssl_type}"
      LETSENCRYPT_EMAIL="${var.letsencrypt_email}"
    }
  }    
}
