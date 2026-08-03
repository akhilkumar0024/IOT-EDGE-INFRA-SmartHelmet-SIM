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

# ROLE 1: Application Deployment Pipeline Role (smart-helmet-app-deploy-role)
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
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
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
          "arn:aws:ecr:ap-south-1:167378055060:repository/smart-helmet-telemetry-service-repo",
          "arn:aws:ecr:ap-south-1:167378055060:repository/smart-helmet-processing-service-repo",
          "arn:aws:ecr:ap-south-1:167378055060:repository/smart-helmet-alert-service-repo"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeClusters",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "arn:aws:ecs:ap-south-1:167378055060:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "deploy_attach" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.deploy_policy.arn
}

# ROLE 2: Terraform PR Plan Check Role (smart-helmet-tf-plan-role)
resource "aws_iam_role" "github_actions_tf_plan" {
  name = var.plan_role_name

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

resource "aws_iam_policy" "tf_plan_policy" {
  name        = "${var.plan_role_name}Policy"
  description = "Read-only policy for GitHub Actions Terraform PR plan validation."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes", "sqs:ListQueues", "sqs:ListQueueTags",
          "dynamodb:DescribeTable", "dynamodb:ListTables", "dynamodb:DescribeContinuousBackups",
          "states:DescribeStateMachine", "states:ListStateMachines",
          "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcAttribute",
          "ecr:DescribeRepositories", "ecr:ListTagsForResource",
          "ecs:DescribeClusters", "ecs:DescribeServices",
          "logs:DescribeLogGroups",
          "iot:DescribeEndpoint", "iot:DescribeCertificate", "iot:GetPolicy",
          "sns:GetTopicAttributes",
          "ssm:GetParameter", "ssm:GetParameters",
          "iam:GetRole", "iam:GetPolicy", "iam:GetOpenIDConnectProvider"
        ]
        Resource = [
          "arn:aws:sqs:ap-south-1:167378055060:smart-helmet-*",
          "arn:aws:dynamodb:ap-south-1:167378055060:table/smart-helmet-*",
          "arn:aws:states:ap-south-1:167378055060:stateMachine:smart-helmet-*",
          "arn:aws:ec2:ap-south-1:167378055060:*",
          "arn:aws:ecr:ap-south-1:167378055060:repository/smart-helmet-*",
          "arn:aws:ecs:ap-south-1:167378055060:*",
          "arn:aws:logs:ap-south-1:167378055060:log-group:*",
          "arn:aws:sns:ap-south-1:167378055060:smart-helmet-*",
          "arn:aws:ssm:ap-south-1:167378055060:parameter/smart-helmet/*",
          "arn:aws:iot:ap-south-1:167378055060:*",
          "arn:aws:iam::167378055060:*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = "arn:aws:s3:::smarthelmet-terraform-state"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::smarthelmet-terraform-state/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tf_plan_attach" {
  role       = aws_iam_role.github_actions_tf_plan.name
  policy_arn = aws_iam_policy.tf_plan_policy.arn
}

# ROLE 3: Terraform Main Branch Deploy Role (smart-helmet-tf-deploy-role)
resource "aws_iam_role" "github_actions_tf_deploy" {
  name = var.apply_role_name

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
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "tf_deploy_policy" {
  name        = "${var.apply_role_name}Policy"
  description = "Provisioning and management policy for GitHub Actions Terraform live deployments on main branch."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:*",
          "dynamodb:*",
          "states:*",
          "ec2:*",
          "ecr:*",
          "ecs:*",
          "logs:*",
          "sns:*",
          "ssm:*",
          "iot:*",
          "iam:*"
        ]
        Resource = [
          "arn:aws:sqs:ap-south-1:167378055060:smart-helmet-*",
          "arn:aws:dynamodb:ap-south-1:167378055060:table/smart-helmet-*",
          "arn:aws:states:ap-south-1:167378055060:stateMachine:smart-helmet-*",
          "arn:aws:ec2:ap-south-1:167378055060:*",
          "arn:aws:ecr:ap-south-1:167378055060:repository/smart-helmet-*",
          "arn:aws:ecs:ap-south-1:167378055060:*",
          "arn:aws:logs:ap-south-1:167378055060:log-group:*",
          "arn:aws:sns:ap-south-1:167378055060:smart-helmet-*",
          "arn:aws:ssm:ap-south-1:167378055060:parameter/smart-helmet/*",
          "arn:aws:iot:ap-south-1:167378055060:*",
          "arn:aws:iam::167378055060:*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = "arn:aws:s3:::smarthelmet-terraform-state"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::smarthelmet-terraform-state/*"
      },
      # Prevent Privilege Escalation (Role cannot modify or delete its own policy)
      {
        Effect = "Deny"
        Action = [
          "iam:PutRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:DeleteRole"
        ]
        Resource = [
          "arn:aws:iam::167378055060:role/smart-helmet-tf-deploy-role",
          "arn:aws:iam::167378055060:policy/smart-helmet-tf-deploy-rolePolicy"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tf_deploy_attach" {
  role       = aws_iam_role.github_actions_tf_deploy.name
  policy_arn = aws_iam_policy.tf_deploy_policy.arn
}
