# Security Group for ECS Fargate Tasks
resource "aws_security_group" "ecs_infra_sg" {
  name        = "smart-helmet-ecs-infra-sg"
  description = "Shared security group for ECS microservices"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "smart-helmet-ecs-infra-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ecs_infra_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
