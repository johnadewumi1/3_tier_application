output "s3" {
  description = "s3 outputs"
  value       = module.s3_bucket
}

output "ec2_role" {
    description = "iam ec2 role outputs"
    value = module.ec2_role_custom
}

output "s3bucket_policy" {
    description = "iam s3 policy outputs"
    value = module.iam_policy_for_s3
}

output "vpc" {
    description = "vpc outputs"
    value = module.vpc
}

output "security-group" {
  description = "security group outputs"
  value = module.security_group
}

output "alb" {
  value = module.alb
}
