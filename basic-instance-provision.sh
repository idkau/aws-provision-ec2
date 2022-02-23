#!/bin/bash
#
#Version: 1.0
#
#Provision a managed VPS ec2 instance and modify the disk size to 200G
#Allocate and associate elastic IP with instance
#
#by Jason
#Questions: jason@someemail.com
#
CP_TEMPLATE="WHM-CL8-tpl"
OS_TYPE="Cloudlinux"
OS_VERSION="8"
VOLUME_SIZE="200"
#Change to the required SG for cpanel/cloudlinux managed vps
SECURITY_GROUP_ID="sg-0aaXXXXXXX"
IS_MANAGED="True"
isRunning="stopped"
isAttached="no"

read -p 'Enter the customer email address: ' customerEmail
read -p 'Enter the VPS ID: ' vpsID
read -p 'Enter the Greencode: ' greenCode
read -p "****************************
*  t3.small    2CPU/2GRAM  *
*  t3.medium   2CPU/4GRAM  *
*  c5a.large   2CPU/4GRAM  *
*  c5a.xlarge  4CPU/8GRAM  *
****************************
Enter the Instance Type (ex. t3.medium): " instanceType


#change all case to lower for var instancetype
instanceType=$(echo $instanceType | tr '[:upper:]' '[:lower:]')

#Set bandwidth based on instance type
case $instanceType in
    t3.small | t3.medium)
    bandwidth="204800"
        ;;
    c5a.large)
    bandwidth="409600"
        ;;
    c5a.xlarge)
    bandwidth="819200"
        ;;
esac

#Get the newest backup of the cloudlinux 8 cpanel tempolate AMI from backup
imageId=$(aws ec2 describe-images --owners self --filters "Name=tag:Name, Values=${CP_TEMPLATE}" --query 'Images[*].[ImageId]' --output text | head -1)

if [[ -z "$imageId" ]]; then
    #statements
    echo "Image ID is empty"; exit 1
fi


#JSON tags for next line
tagSpecs=$(echo "ResourceType=instance,Tags=[{Key=CustomerEmail,Value=${customerEmail}},{Key=Type,Value=VPS},{Key=Backup,Value=Managed},{Key=Name,Value=${vpsID}},{K
ey=Monitoring,Value=true},{Key=AccountName,Value=${greenCode}},{Key=Managed,Value=${IS_MANAGED}},{Key=Bandwidth,Value=${bandwidth}},{Key=OS,Value=${OS_TYPE}},{Key=OSVersion,Value=${OS_VERSION}}]")

#create instance
aws ec2 run-instances --image-id $imageId --count 1 --instance-type $instanceType --key-name tpp-vps --security-group-ids $SECURITY_GROUP_ID --subnet-id subnet-001XXXXXXXXXX --tag-specifications $tagSpecs

if [[ -z "$imageId" ]]; then

    echo "Image ID is empty"; exit 1
fi

if [[ -z "$instanceType" ]]; then

    echo "Instance Type is empty"; exit 1
fi

echo "Creating a new instance $instanceType for VPS $vpsID, please wait..."

#waiting for instance volume to reach attached state
while [ $isAttached != "attached" ]
do

isAttached=$(aws ec2 describe-instances --filters "Name=tag:Name, Values=$vpsID" --query 'Reservations[*].Instances[*].BlockDeviceMappings[*]' --output text | tail -1 | cut -f 4)


echo "Waiting for volume to attach to instance..."

sleep 5
done

#get new volume ID from newly provisioned instance
volumeIdAttachedToNewEc2=$(aws ec2 describe-instances --filters "Name=tag:Name, Values=$vpsID" --query 'Reservations[*].Instances[*].BlockDeviceMappings[*]' --output text | tail -1 | cut -f 5)

aws ec2 modify-volume --size $VOLUME_SIZE --volume-id $volumeIdAttachedToNewEc2

echo "Resizing volume..."

sleep 2

#add VPS ID tag to volume
aws ec2 create-tags --resources $volumeIdAttachedToNewEc2 --tags "Key=Name,Value=$vpsID"

#Get allocation ID from newly allocated IP.
elasticIpAllocationId=$(aws ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${vpsID}}]" | grep AllocationId | cut -d '"' -f 4)


#Get instance ID of new instance
instanceId=$(aws ec2 describe-instances --filters "Name=tag:Name, Values=$vpsID" --query 'Reservations[*].Instances[*].InstanceId' --output text)


#waiting for instance to reach running state
while [ $isRunning != "running" ]
do

isRunning=$(aws ec2 describe-instance-status --instance-ids $instanceId --query "InstanceStatuses[*].[InstanceState]" --output text | cut -f 2)


echo "Waiting for instance to reach running status to associate Elastic IP..."

sleep 5
done

echo "The instance is now running... Associating Elastic IP with instance..."

#Associate IP with new EC2 instance
aws ec2 associate-address --instance-id $instanceId --allocation-id $elasticIpAllocationId


sleep 2

echo "Success! The instance has been provisioned."


##### needs the modification code to grow partition to match the volume.
