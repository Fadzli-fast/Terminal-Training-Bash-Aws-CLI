#!/bin/bash

# Cleanup script for Tyk Training Environment
# Removes all resources created by deploy-tyk-training.sh

set -e

REGION="${1:-ap-southeast-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "Starting cleanup of Tyk Training Environment in region: $REGION"

# Find and terminate instances
print_status "Finding and terminating instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=tyk-training-*" "Name=instance-state-name,Values=running,stopped,pending" \
    --region "$REGION" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ -n "$INSTANCE_IDS" ]; then
    print_status "Terminating instances: $INSTANCE_IDS"
    aws ec2 terminate-instances \
        --instance-ids $INSTANCE_IDS \
        --region "$REGION"
    
    print_status "Waiting for instances to terminate..."
    aws ec2 wait instance-terminated \
        --instance-ids $INSTANCE_IDS \
        --region "$REGION"
    print_status "Instances terminated"
else
    print_warning "No instances found to terminate"
fi

# Delete security group
print_status "Deleting security group..."
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=tyk-training-sg" \
    --region "$REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    print_status "Deleting security group: $SG_ID"
    aws ec2 delete-security-group \
        --group-id "$SG_ID" \
        --region "$REGION"
    print_status "Security group deleted"
else
    print_warning "No security group found to delete"
fi

# Delete subnet
print_status "Deleting subnet..."
SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=tyk-training-subnet" \
    --region "$REGION" \
    --query 'Subnets[0].SubnetId' \
    --output text 2>/dev/null || echo "")

if [ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "None" ]; then
    print_status "Deleting subnet: $SUBNET_ID"
    aws ec2 delete-subnet \
        --subnet-id "$SUBNET_ID" \
        --region "$REGION"
    print_status "Subnet deleted"
else
    print_warning "No subnet found to delete"
fi

# Delete route table
print_status "Deleting route table..."
RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=tyk-training-rt" \
    --region "$REGION" \
    --query 'RouteTables[0].RouteTableId' \
    --output text 2>/dev/null || echo "")

if [ -n "$RT_ID" ] && [ "$RT_ID" != "None" ]; then
    print_status "Deleting route table: $RT_ID"
    aws ec2 delete-route-table \
        --route-table-id "$RT_ID" \
        --region "$REGION"
    print_status "Route table deleted"
else
    print_warning "No route table found to delete"
fi

# Detach and delete internet gateway
print_status "Deleting internet gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=tyk-training-igw" \
    --region "$REGION" \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text 2>/dev/null || echo "")

if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    VPC_ID=$(aws ec2 describe-internet-gateways \
        --internet-gateway-ids "$IGW_ID" \
        --region "$REGION" \
        --query 'InternetGateways[0].Attachments[0].VpcId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        print_status "Detaching internet gateway: $IGW_ID from VPC: $VPC_ID"
        aws ec2 detach-internet-gateway \
            --internet-gateway-id "$IGW_ID" \
            --vpc-id "$VPC_ID" \
            --region "$REGION"
    fi
    
    print_status "Deleting internet gateway: $IGW_ID"
    aws ec2 delete-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --region "$REGION"
    print_status "Internet gateway deleted"
else
    print_warning "No internet gateway found to delete"
fi

# Delete VPC
print_status "Deleting VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=tyk-training-vpc" \
    --region "$REGION" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || echo "")

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    print_status "Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc \
        --vpc-id "$VPC_ID" \
        --region "$REGION"
    print_status "VPC deleted"
else
    print_warning "No VPC found to delete"
fi

print_status "🎉 Cleanup completed successfully!"
print_status "All Tyk Training Environment resources have been removed from region: $REGION"
