##############################################################
# Copyright 2024 Massdriver, Inc
#
# This script downloads and installs the MGN replication agent
# from the specified region, then installs the agent using 
# short lived credentials.
#
##############################################################

param (
    [string]$AWSAccountID,
    [string]$AWSRegion,
    [string]$SourceServerName,
    [string]$AWSAccessKeyID,
    [string]$AWSSecretAccessKey,
    [string]$AWSSessionToken
)

if (-not $AWSAccountID -or -not $AWSRegion -or -not $SourceServerName -or -not $AWSAccessKeyID -or -not $AWSSecretAccessKey -or -not $AWSSessionToken) {
    Write-Error "All parameters are required. Usage:"
    Write-Error "./install_agent_windows.ps1 -AWSAccountID <account-id> -AWSRegion <region> -SourceServerName <server-name> -AWSAccessKeyID <access-key> -AWSSecretAccessKey <secret-key> -AWSSessionToken <session-token>"
    exit 1
}

if ($AWSRegion -notmatch "^[a-z]{2}-[a-z]+-[0-9]$") {
    Write-Error "Invalid AWS region format. Please enter a valid region (e.g., us-east-1)."
    exit 1
}

$InstallerURL = "https://aws-application-migration-service-$AWSRegion.s3.$AWSRegion.amazonaws.com/latest/windows/AwsReplicationWindowsInstaller.exe"

$InstallerPath = ".\AwsReplicationWindowsInstaller.exe"
Write-Host "Downloading AWS Replication Windows Installer from $InstallerURL..."
Invoke-WebRequest -Uri $InstallerURL -OutFile $InstallerPath -ErrorAction Stop

if (-Not (Test-Path $InstallerPath)) {
    Write-Error "Failed to download the installer. Please check the AWS region and network connection."
    exit 1
}

Write-Host "Download complete. Starting the installation process..."

$InstallCommand = "& `"$InstallerPath`" --region $AWSRegion --aws-access-key-id $AWSAccessKeyID --aws-secret-access-key $AWSSecretAccessKey --aws-session-token $AWSSessionToken --user-provided-id $SourceServerName"

try {
    Invoke-Expression $InstallCommand
    Write-Host "AWS replication agent successfully installed."
} catch {
    Write-Error "Installation failed: $_"
    exit 1
}
