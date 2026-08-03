#!/bin/bash

# Ensure we are in the project root
cd "$(dirname "$0")/.." || exit 1

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-south-1"

echo "Logging into AWS ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

echo "----------------------------------------"
echo "Building and pushing Telemetry Processor..."
docker build --no-cache -t smart-helmet-telemetry-service-repo ./Application/telemetry-processor
docker tag smart-helmet-telemetry-service-repo:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/smart-helmet-telemetry-service-repo:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/smart-helmet-telemetry-service-repo:latest

echo "----------------------------------------"
echo "Building and pushing Processing Engine..."
docker build --no-cache -t smart-helmet-processing-service-repo ./Application/processing-engine
docker tag smart-helmet-processing-service-repo:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/smart-helmet-processing-service-repo:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/smart-helmet-processing-service-repo:latest

echo "----------------------------------------"
echo "Building and pushing Alert Handler..."
docker build --no-cache -t smart-helmet-alert-service-repo ./Application/alert-handler
docker tag smart-helmet-alert-service-repo:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/smart-helmet-alert-service-repo:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/smart-helmet-alert-service-repo:latest

echo "----------------------------------------"
echo "All microservice container images pushed successfully!"
