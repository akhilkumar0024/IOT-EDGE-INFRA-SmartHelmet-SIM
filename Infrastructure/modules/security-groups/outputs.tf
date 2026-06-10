output "aws-sg-ecs-infra-id" {
  value = aws_security_group.ecs-infra-sg.id
}

output "aws-sg-ecs-infra-name" {
  value = aws_security_group.ecs-infra-sg.name
}
