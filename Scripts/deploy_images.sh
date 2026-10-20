#!/bin/bash
#
# Manual / bootstrap image push.
#
# CI is the normal path - see .github/workflows/svc-*.yaml, which both builds the
# image and rolls the ECS service onto it. This script exists for a fresh
# bootstrap, where Terraform has created the ECR repositories and the ECS
# services but no image exists yet.
#
# Tags are "<commit-sha>-manual-<epoch>" rather than ":latest" because the
# repositories are IMMUTABLE:
#   - a moving tag like ":latest" cannot be pushed a second time
#   - a bare commit SHA would collide if the same commit were built twice
#
# Note this only pushes. It does not deploy - run the service's CI workflow, or
# `aws ecs update-service`, to actually roll the service.

set -euo pipefail

# Ensure we are in the project root
cd "$(dirname "$0")/.." || exit 1

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="${AWS_REGION:-ap-south-1}"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
TAG="$(git rev-parse HEAD)-manual-$(date +%s)"

echo "Logging into AWS ECR ($REGISTRY)..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

push_image() {
  local repo="$1"
  local context="$2"
  echo "----------------------------------------"
  echo "Building and pushing $repo"
  docker build --no-cache -t "$REGISTRY/$repo:$TAG" "$context"
  docker push "$REGISTRY/$repo:$TAG"
}

# Note the repository name for alerts is singular ("alert-service-repo") while
# the ECS service is plural ("alerts-service") - see TODO §5.11.
push_image smart-helmet-telemetry-service-repo ./services/telemetry-processor
push_image smart-helmet-processing-service-repo ./services/processing-engine
push_image smart-helmet-alert-service-repo ./services/alert-handler

echo "----------------------------------------"
echo "Pushed tag: $TAG"
echo "This only pushed images. CI is what deploys them."
