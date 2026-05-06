output "frontend_url" {
  value       = "http://${aws_instance.frontend.public_ip}"
  description = "Open this in your browser — Angular app"
}

output "alb_dns" {
  value       = "http://${aws_lb.backend.dns_name}"
  description = "Backend ALB — all API calls go here"
}

output "health_check_url" {
  value       = "http://${aws_lb.backend.dns_name}/health"
  description = "Should return 200 OK when backend is healthy"
}

output "rds_endpoint" {
  value       = aws_db_instance.mysql.address
  description = "MySQL endpoint (private — only backend EC2 can reach this)"
}

output "backend_asg_name" {
  value       = aws_autoscaling_group.backend.name
  description = "Use this in AWS Console to check ASG instances"
}