#!/bin/bash

# Check if an input file is provided as an argument
if [ -z "$1" ]; then
    echo "Please provide an input file as an argument"
    exit 1
fi

input_file="$1"
input_file_name=$(basename "$input_file" .txt)  # Remove the .txt extension
output_dir="ChIP_process/${input_file_name%_SRR_Acc_List}_SRAfile"  # Dynamically generate the output directory name

# Check if the input file exists
if [ ! -f "$input_file" ]; then
    echo "File $input_file does not exist"
    exit 1
fi

# Create the output directory
mkdir -p "$output_dir"

# Read each line from the input file
while IFS= read -r srr_id; do
    srr_id=$(echo "$srr_id" | xargs)  # Trim leading and trailing spaces
    if [ -z "$srr_id" ]; then
        echo "Skipping empty line"
        continue
    fi

    echo "Downloading SRR ID: $srr_id"
    retry_count=0
    success=false

    # Retry downloading up to 3 times
    while [ $retry_count -lt 3 ]; do
        if prefetch -O "$output_dir" "$srr_id"; then
            success=true
            break
        else
            retry_count=$((retry_count + 1))
            echo "Download failed, retrying ($retry_count/3)"
        fi
    done

    # If download fails after 3 attempts, log the failed SRR ID
    if [ "$success" = false ]; then
        echo "SRR ID $srr_id failed to download after 3 attempts"
        echo "$srr_id" >> "${output_dir}/failed_SRRs.txt"
    fi

done < "$input_file"

echo "All downloads completed"
