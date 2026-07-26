# 1. Fetch GitHub's OIDC OpenID configuration dynamically
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# 2. OpenID Connect Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# ROLE 1: Application Deployment Pipeline Role (GithubActionsDeployCode)
resource "aws_iam_role" "github_actions_deploy" {
  name = var.deploy_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "deploy_policy" {
  name        = "${var.deploy_role_name}Policy"
  description = "Policy for GitHub Actions App Deployment (ECR image push and ECS Fargate updates)."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Account-level ECR login token
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      # Image push scoped strictly to the 3 microservice ECR repositories
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories"
        ]
        Resource = [
          "arn:aws:ecr:ap-south-1:167378055060:repository/telemetry-service-repo",
          "arn:aws:ecr:ap-south-1:167378055060:repository/processing-service-repo",
          "arn:aws:ecr:ap-south-1:167378055060:repository/alert-service-repo"
        ]
      },
      # ECS Fargate zero-downtime service deployment permissions
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeClusters",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "deploy_attach" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.deploy_policy.arn
}

# ROLE 2: Terraform PR Checks Pipeline Role (GithubActionsTerraformCheck)
resource "aws_iam_role" "github_actions_terraform" {
  name = var.terraform_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "terraform_policy" {
  name        = "${var.terraform_role_name}Policy"
  description = "Read-Only policy for GitHub Actions Terraform PR validation and plan generation."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:ListQueues",
          "dynamodb:DescribeTable",
          "dynamodb:ListTables",
          "states:DescribeStateMachine",
          "states:ListStateMachines",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ecr:DescribeRepositories",
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "iot:DescribeEndpoint"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_attach" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.terraform_policy.arn
}
