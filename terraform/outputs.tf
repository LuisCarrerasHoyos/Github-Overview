output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.web_alb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.postgres.endpoint
}

output "generated_db_password" {
  description = "The auto-generated database password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "availability_zones" {
  description = "Availability zones used in the deployment"
  value       = data.aws_availability_zones.available.names
}