#!/bin/bash

# Check if an input file parameter is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <input_file_path>"
    exit 1
fi

input_file="$1"

# Check if the file exists
if [ ! -f "$input_file" ]; then
    echo "File $input_file does not exist"
    exit 1
fi

# File to log failed SRR downloads
failed_srr_log="failed_srr_downloads.log"
: > "$failed_srr_log"

# Read each line in the file
while IFS= read -r srr_id; do
    echo "Downloading SRR ID: $srr_id"
    retries=0
    success=false

    # Retry download logic
    while [ $retries -lt 3 ] && [ "$success" = false ]; do
        prefetch "$srr_id"
        if [ $? -eq 0 ]; then
            success=true
            echo "SRR ID: $srr_id downloaded successfully"
        else
            retries=$((retries + 1))
            echo "SRR ID: $srr_id download failed, retrying $retries/3..."
            sleep 2  # Optional: Wait for a short period between retries
        fi
    done

    # If download fails after 3 attempts, log the failure and move to the next SRR ID
    if [ "$success" = false ]; then
        echo "SRR ID: $srr_id download failed, skipped and logged"
        echo "SRR ID: $srr_id" >> "$failed_srr_log"
    fi
done < "$input_file"

echo "All download attempts completed, failed SRR IDs logged in $failed_srr_log"
