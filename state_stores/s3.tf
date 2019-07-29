provider "aws" {
  profile = "${var.aws_profile}"
  region  = "${var.aws_region}"
}

resource "aws_s3_bucket" "terraform_state_store" {
  bucket = "rancher-${var.cluster_name}-terraform"
  acl    = "private"
  tags = {
    Name        = "rancher-${var.cluster_name}-terraform"
    Owner = "${var.prefix}"
  }
}

resource "aws_s3_bucket" "rancher_backups" {
  bucket = "rancher-${var.cluster_name}-backups"
  acl    = "private"
  tags = {
    Name        = "rancher-${var.cluster_name}-backups"
    Owner = "${var.prefix}"
  }
}

data "template_file" "backendConfig" {
  template = <<EOF
bucket  = "rancher-${var.cluster_name}-terraform"
key     = "${var.cluster_name}.tfstate"
region  = "${var.aws_region}"
profile = "${var.aws_profile}"
EOF
}

resource "local_file" "backendConfig" {
    content     = "${data.template_file.backendConfig.rendered}"
    filename = "${path.module}/backends/backend-${var.cluster_name}.conf"
}
