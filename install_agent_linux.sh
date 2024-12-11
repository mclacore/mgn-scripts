#!/bin/bash

##############################################################
# Copyright 2024 Massdriver, Inc
#
# This script downloads and installs the MGN replication agent
# from the specified region, then installs the agent using 
# short lived credentials.
#
##############################################################

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 <AWS_ACCOUNT_ID> <AWS_REGION> <SERVER_NAME> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <AWS_SESSION_TOKEN>"
  echo "Example: $0 123456789012 us-east-1 my-server AKIAEXAMPLE SECRETEXAMPLE TOKENEXAMPLE"
  exit 1
fi

AWS_ACCOUNT=$1
AWS_REGION=$2
SERVER_NAME=$3
AWS_ACCESS_KEY_ID=$4
AWS_SECRET_ACCESS_KEY=$5
AWS_SESSION_TOKEN=$6

if [[ ! $AWS_REGION =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
  echo "Error: Invalid AWS region format. Expected format is something like 'us-east-1'."
  exit 1
fi

AGENT_URL="https://aws-application-migration-service-$AWS_REGION.s3.$AWS_REGION.amazonaws.com/latest/linux/aws-replication-installer-init"

echo "Downloading agent from $AGENT_URL..."
wget -O ./aws-replication-installer-init "$AGENT_URL"

if [[ $? -ne 0 ]]; then
  echo "Download failed. Please check your AWS region and network connection."
  exit 1
fi

sudo chmod +x ./aws-replication-installer-init

echo "Download complete and file made executable."

echo "Installing AWS replication agent..."
sudo ./aws-replication-installer-init \
  --region $AWS_REGION \
  --aws-access-key-id "$AWS_ACCESS_KEY_ID" \
  --aws-secret-access-key "$AWS_SECRET_ACCESS_KEY" \
  --aws-session-token "$AWS_SESSION_TOKEN" \
  --user-provided-id "$SERVER_NAME"

if [[ $? -eq 0 ]]; then
  echo "AWS replication agent successfully installed."
else
  echo "Installation failed. Please check the inputs and try again."
  exit 1
fi
