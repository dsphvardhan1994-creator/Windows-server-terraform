output "instance_id" {
  description = "EC2 instance ID; find it in Systems Manager Fleet Manager."
  value       = aws_instance.windows.id
}

output "public_ip" {
  description = "Public IP; no inbound security group rules are configured."
  value       = aws_instance.windows.public_ip
}

output "fleet_manager_operator_policy_arn" {
  description = "Attach this policy to the AWS identity initiating Fleet Manager Remote Desktop."
  value       = aws_iam_policy.fleet_manager_operator.arn
}

output "instance_role_arn" {
  description = "EC2 instance role ARN with SSM core and AdministratorAccess."
  value       = aws_iam_role.instance.arn
}
