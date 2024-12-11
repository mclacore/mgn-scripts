#!/bin/bash

################################################################
# Copyright 2024 Massdriver, Inc
#
# This script checks for (or creates) an S3 bucket to upload
# an MGN inventory spreadsheet. It then takes an existing CSV
# named aws-application-migration-service-import.csv and uploads
# the file to the AWS S3 bucket. It then starts an MGN import
# task to import the inventory into AWS MGN.
#
################################################################

read -p "Enter the AWS region (e.g., us-west-2): " AWS_REGION

CSV_FILE="./aws-application-migration-service-import.csv"
S3_BUCKET="massdriver-mgn-import"
S3_KEY="mgn-imports/${CSV_FILE}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [[ ! -f "$CSV_FILE" ]]; then
    echo "Error: CSV file '$CSV_FILE' not found."
    exit 1
fi

echo "Checking if the S3 bucket '$S3_BUCKET' exists..."
if ! aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
    echo "Bucket '$S3_BUCKET' does not exist. Creating it..."
    aws s3api create-bucket \
        --bucket "$S3_BUCKET" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create bucket '$S3_BUCKET'."
        exit 1
    fi
    echo "Bucket '$S3_BUCKET' created successfully."
else
    echo "Bucket '$S3_BUCKET' already exists."
fi

echo "Uploading CSV file to S3..."
aws s3 cp "$CSV_FILE" "s3://$S3_BUCKET/$S3_KEY" --region "$AWS_REGION"

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to upload CSV file to S3."
    exit 1
fi
echo "CSV file uploaded successfully to s3://$S3_BUCKET/$S3_KEY."

echo "Starting the import process in AWS MGN..."
aws mgn start-import \
    --region "$AWS_REGION" \
    --s3-bucket-source "s3Bucket=$S3_BUCKET,s3BucketOwner=$ACCOUNT_ID,s3Key=$S3_KEY"

if [[ $? -eq 0 ]]; then
    echo "Import process started successfully."
else
    echo "Error: Import process failed."
    exit 1
fi
