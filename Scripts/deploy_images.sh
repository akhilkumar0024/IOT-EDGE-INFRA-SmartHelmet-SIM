#!/bin/bash

# Ensure we are in the project root
cd "$(dirname "$0")/.." || exit 1

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-south-1"

echo "Logging into AWS ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

echo "----------------------------------------"
echo "Building and pushing Telemetry Processor..."
docker build --no-cache -t telemetry-service-repo ./Application/telemetry-processor
docker tag telemetry-service-repo:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/telemetry-service-repo:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/telemetry-service-repo:latest

echo "----------------------------------------"
echo "Building and pushing Processing Engine..."
docker build --no-cache -t processing-service-repo ./Application/processing-engine
docker tag processing-service-repo:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/processing-service-repo:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/processing-service-repo:latest

echo "----------------------------------------"
echo "Building and pushing Alert Handler..."
docker build --no-cache -t alert-service-repo ./Application/alert-handler
docker tag alert-service-repo:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/alert-service-repo:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/alert-service-repo:latest

echo "----------------------------------------"
echo "All images deployed successfully!"
