resource "aws_iam_role_policy" "control_plane_role_policy" {
  name   = "${var.cluster_name}_control_plane_role_policy"
  role = "${aws_iam_role.control_plane_role.id}"
  policy = "${file("aws/control-plane-iam-policy.json")}"
}

resource "aws_iam_role" "control_plane_role" {
  name = "${var.cluster_name}-control_plane_role"
  assume_role_policy = "${file("aws/assume-role-policy.json")}"
}

resource "aws_iam_instance_profile" "control_plane_instance_profile" {
  name = "${var.cluster_name}-control_plane_instance_profile"
  role = "${aws_iam_role.control_plane_role.name}"
}

resource "aws_iam_role_policy" "worker_node_policy" {
  name   = "${var.cluster_name}-worker_node_policy"
  role = "${aws_iam_role.worker_node_role.id}"
  policy = "${file("aws/worker-node-iam-policy.json")}"
}

resource "aws_iam_role" "worker_node_role" {
  name = "${var.cluster_name}-worker_node_role"
  assume_role_policy = "${file("aws/assume-role-policy.json")}"
}

resource "aws_iam_instance_profile" "worker_node_instance_profile" {
  name = "${var.cluster_name}-worker_node_instance_profile"
  role = "${aws_iam_role.worker_node_role.name}"
}


