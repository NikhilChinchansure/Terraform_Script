output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "alb_ingress_iam_policy" {
  value = data.aws_iam_policy_document.alb_controller.json
}
