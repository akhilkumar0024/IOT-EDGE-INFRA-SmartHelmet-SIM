resource "aws_security_group" "ecs-infra-sg" {
  name        = "ECS-infra-SG"
  description = "Allow to read data from the Telemtry Queue"
  vpc_id      = var.vpc-id

  tags = {
    Name = "ECS-infra-SG"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ecs-infra-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # -1 is equivalent of all ports
}
