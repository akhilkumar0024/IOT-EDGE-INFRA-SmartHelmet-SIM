data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/smart-helmet-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeClusters",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/smart-helmet-*"
        ]
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
          "ec2:Describe*",
          "ecr:DescribeRepositories", "ecr:ListTagsForResource",
          "ecs:DescribeClusters", "ecs:DescribeServices", "ecs:DescribeTaskDefinition",
          "logs:DescribeLogGroups",
          "cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource",
          "application-autoscaling:Describe*",
          "iot:DescribeEndpoint", "iot:DescribeCertificate", "iot:GetPolicy", "iot:ListTopicRules",
          "sns:GetTopicAttributes",
          "ssm:GetParameter", "ssm:GetParameters", "ssm:DescribeParameters",
          "iam:GetRole", "iam:GetPolicy", "iam:GetOpenIDConnectProvider"
        ]
        Resource = "*"
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
          "ec2:Describe*",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListTagsForResource",
          "application-autoscaling:Describe*",
          "ssm:DescribeParameters",
          "iot:DescribeEndpoint",
          "iot:ListTopicRules",
          "logs:DescribeLogGroups",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "iam:GetOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders"
        ]
        Resource = "*"
      },
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
          "iam:*",
          "cloudwatch:*",
          "application-autoscaling:*"
        ]
        Resource = [
          "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:smart-helmet-*",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/smart-helmet-*",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/terraform-state-lock",
          "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:SmartHelmet*",
          "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:smart-helmet-*",
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*",
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/smart-helmet-*",
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/smart-helmet-*",
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/smart-helmet-*/*",
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*",
          "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:smart-helmet-*",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/smart-helmet/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/smart-helmet-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/smart-helmet-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/*",
          "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alarm:smart-helmet-*",
          "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alarm:iot-core-*",
          "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alarm:TargetTracking-*",
          "arn:aws:application-autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:scalable-target/*",
          "arn:aws:application-autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:scaling-policy:*"
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
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/smart-helmet-tf-deploy-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/smart-helmet-tf-deploy-rolePolicy",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/smart-helmet-tf-plan-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/smart-helmet-tf-plan-rolePolicy",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/smart-helmet-app-deploy-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/smart-helmet-app-deploy-rolePolicy"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tf_deploy_attach" {
  role       = aws_iam_role.github_actions_tf_deploy.name
  policy_arn = aws_iam_policy.tf_deploy_policy.arn
}
