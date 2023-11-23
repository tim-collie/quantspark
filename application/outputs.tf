output "quantspark_webserver_load_balancer_dns" {
  value = aws_lb.quantspark_alb.dns_name
}