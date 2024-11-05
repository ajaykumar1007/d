#!/bin/bash

# Variables
ZONE="us-central1-f"
DISK_NAME1="instance--120034"
# DISK_NAME2="instance--051856"

# Function to calculate new disk size (current size + 10%)
calculate_new_size() {
    current_size_gb=$1
    increase_size=$(( current_size_gb / 10 ))   # Increase by 10%
    new_size=$(( current_size_gb + increase_size ))

    # Ensure the new size is at least 1 GB larger than the current size
    if [ $increase_size -le 0 ]; then
        new_size=$(( current_size_gb + 1 ))  # Increase by at least 1GB if the current size is too small
    fi

    echo $new_size
}

# Function to check and resize a disk
resize_disk() {
    local path=$1
    local disk_name=$2
    local filesystem=$3

    # Determine the appropriate device for the specified path
    device=$(df --output=source "$path" | tail -1)
    disk_usage=$(df -h "$path" | awk 'NR==2{print $5}' | tr -d '%')  # Disk usage percentage without %
    
    # Get current disk size in GB
    current_size=$(lsblk -b -o SIZE -n -d "${device%[0-9]*}" | awk '{print int($1/1024/1024/1024)}')

    echo "Checking $path usage: ${disk_usage}% (Current size: ${current_size}GB, Filesystem: $filesystem)"

    # Check if usage is above 80%
    if [ "$disk_usage" -ge 80 ]; then
        # Calculate new size
        new_size=$(calculate_new_size "$current_size")

        # Ensure the new size is greater than the current size
        if [ "$new_size" -le "$current_size" ]; then
            echo "Calculated new size ($new_size GB) is not greater than current size ($current_size GB). No resize action will be taken."
            return  # Exit the function early
        fi

        # Resize the disk
        echo "Usage above 80% on $path. Resizing disk to ${new_size}GB..."
        gcloud compute disks resize "$disk_name" --size="${new_size}"GB --zone="$ZONE" --quiet
        
        echo "Disk resized to ${new_size}GB."
        
        # Resize filesystem
        if [ "$filesystem" == "ext4" ]; then
            sudo growpart "${device%[0-9]*}" "${device##*/dev/sda}" 
            sudo resize2fs "$device"
        elif [ "$filesystem" == "xfs" ]; then
            sudo xfs_growfs "$path"
        fi
    else
        echo "Usage is below 80%. No resize needed for $path."
    fi
}

# Check and resize disks for /
resize_disk / "$DISK_NAME1" "ext4"
# Uncomment the next line if you want to check and resize /data as well
# resize_disk /data "$DISK_NAME2" "xfs"
