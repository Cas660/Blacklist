#!/bin/bash

# Define data directory
data_dir="data"

# Function to display usage information
usage() {
    echo "Usage: $0 <genome_file> <kmer_list>"
    echo "  <genome_file> : Name of the genome file in the 'data' folder (e.g., danRer11.fa.gz or mm39.fa)."
    echo "  <kmer_list>   : Comma-separated list of k-mer sizes (e.g., 31,41,51)."
    echo ""
    echo "Example: $0 danRer11.fa.gz 31,41,51"
    exit 1
}

# Check if a file exists
check_file_exists() {
    if [ ! -f "$1" ]; then
        echo "Error: File not found: $1"
        exit 1
    fi
}

# Uncompress a file if it is compressed
uncompress_file() {
    local file="$1"
    if [[ "$file" == *.gz ]]; then
        echo "Uncompressing $file..."
        if gunzip -k "$file"; then
            echo "${file%.gz}"  
        else
            echo "Error: Failed to uncompress $file."
            exit 1
        fi
    else
        echo "$file"  
    fi
}

# Function to run a command with error handling
run_command() {
    local cmd="$1"
    local log_file="$2"
    local err_file="$3"
    echo "Running: $cmd"
    eval "$cmd" >> "$log_file" 2>> "$err_file"
    if [ $? -ne 0 ]; then
        echo "Error: Command failed. Check $err_file for details."
        exit 1
    fi
}

# Export the run_command function so it can be used in sub-shells
export -f run_command

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Error: No arguments provided."
    usage
fi

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

# Assign variables
genome_file="$data_dir/$1"
kmer_list=$2
genome_name=$(basename "$1" .fa)
genome_name=${genome_name%.gz}
chrom_sizes_file="${genome_name}.chrom.sizes"
output_dir="$data_dir/${genome_name}_mappability"
bowtie_dir=$(dirname "$(which bowtie)")
log_dir="$output_dir/logs"
THREADS=4  # Set the number of threads for parallel processing

# Create directories if they don't exist
mkdir -p "$log_dir"
mkdir -p "$output_dir"

# Print the generated directory and file names
echo "Chromosome sizes file will be saved to: $data_dir/$chrom_sizes_file"
echo "Output directory for mappability results: $output_dir"

# Validate inputs
[ -z "$1" ] && { echo "Error: Genome file name not provided."; usage; }
[ -z "$kmer_list" ] && { echo "Error: k-mer list not provided."; usage; }

# Check if the genome file exists (compressed or uncompressed)
check_file_exists "$genome_file" || check_file_exists "${genome_file%.gz}"

# If the file is compressed, uncompress it
genome_file=$(uncompress_file "$genome_file")

# 1. Generate chromosome sizes file using samtools
echo "1/9. Generating chromosome sizes file..."
run_command "samtools faidx \"$genome_file\"" "$log_dir/samtools.log" "$log_dir/samtools.err"
run_command "cut -f1,2 \"${genome_file}.fai\" > \"$data_dir/$chrom_sizes_file\"" "$log_dir/chrsize.log" "$log_dir/chrsize.err"
rm "${genome_file}.fai"

echo "Chromosome sizes saved to $data_dir/$chrom_sizes_file"

# 2. Run ubismap.py
echo "2/9.Running ubismap.py..."
kmer_array=($(echo "$kmer_list" | tr ',' ' '))
for k in "${kmer_array[@]}"; do
    echo "Processing k-mer size: $k"
    run_command "python ubismap.py \"$genome_file\" \"$data_dir/$chrom_sizes_file\" \"$output_dir\" all.q \"$bowtie_dir/bowtie-build\" --kmer \"$k\" -write tem.sh" "$log_dir/ubismap_k${k}.log" "$log_dir/ubismap_k${k}.err"
done
mv "$data_dir/$chrom_sizes_file" "$output_dir/"

# 3. Check maximum chromosome index
echo "3/9. Checking maximum chromosome index..."
if [ -f "$output_dir/chrsize_index.tsv" ]; then
    max_idx=$(tail -1 "$output_dir/chrsize_index.tsv" | awk '{ print $1 + 1 }')
    echo "Maximum chromosome index: $max_idx"
else
    echo "Error: chrsize_index.tsv not found in $output_dir."
    exit 1
fi

# 4. Run bowtie-build to generate the index
echo "4/9.Runing bowtie-build to generate the index..."
if [ -f "$output_dir/genome/Bowtie.1.ebwt" ]; then
    echo "Bowtie index already exists. Skipping index generation."
else
    echo "4/9. Generating Bowtie index..."
    run_command "bowtie-build \"$genome_file\" \"$output_dir/genome/Bowtie\"" "$log_dir/04_bowtie-build.log" "$log_dir/04_bowtie-build.err"
fi

# 5. Get k-mer
echo "5/9.Generating k-mers..."
for k in "${kmer_array[@]}"; do
    echo "Processing k-mer size: $k"

    # Check if the output directory exists
    if [ ! -d "$output_dir/kmers/k$k" ]; then
        echo "Error: Output directory not found: $output_dir/kmers/k$k"
        exit 1
    fi

    log_file="$log_dir/05_get.uniqueKmers_k${k}.LOG"
    err_file="$log_dir/05_get.uniqueKmers_k${k}.ERR"
    > "$log_file"
    > "$err_file"

    # Run get_kmers.py in parallel for each chromosome
    seq 1 $max_idx | xargs -I {} -P $THREADS bash -c "
        run_command \"python get_kmers.py \\\"$output_dir/chrsize.tsv\\\" \\\"$output_dir/kmers/k$k\\\" \\\"$output_dir/chrs\\\" \\\"$output_dir/chrsize_index.tsv\\\" -job_id \\\"{}\\\" --kmer \\\"k$k\\\"\" \"$log_file\" \"$err_file\"
    "
done

# 6. Run Bowtie
echo "6/9.Running Bowtie..."
for k in "${kmer_array[@]}"; do
    echo "Processing k-mer size: $k"
    # Check if the output directory exists
    if [ ! -d "$output_dir/kmers/k$k" ]; then
        echo "Error: Output directory not found: $output_dir/kmers/k$k"
        exit 1
    fi

    log_file="$log_dir/06_run.bowtie_k${k}.LOG"
    err_file="$log_dir/06_run.bowtie_k${k}.ERR"
    > "$log_file"  # Clear the log file
    > "$err_file"  # Clear the error file

    seq 1 $max_idx | xargs -I {} -P $THREADS bash -c "
        run_command \"python run_bowtie.py \\\"$output_dir/kmers/k$k\\\" \\\"$bowtie_dir\\\" \\\"$output_dir/genome\\\" \\\"Bowtie\\\" -job_id \\\"{}\\\"\" \"$log_file\" \"$err_file\"
    "
done

# 7. Run UnifyBowtie
echo "7/9.Running unify_bowtie..."

# Count the number of chromosome files
chr_count=$(find "$output_dir/chrs" -maxdepth 1 -type f -name "*.fasta" | wc -l)
echo "Total number of chromosomes: $chr_count"

for k in "${kmer_array[@]}"; do
    echo "Processing k-mer size: $k"
    # Check if the output directory exists
    if [ ! -d "$output_dir/kmers/k$k" ]; then
        echo "Error: Output directory not found: $output_dir/kmers/k$k"
        exit 1
    fi

    log_file="$log_dir/07_unify.bowtie_k${k}.LOG"
    err_file="$log_dir/07_unify.bowtie_k${k}.ERR"
    > "$log_file"
    > "$err_file"

    # Run unify_bowtie.py for each job_id (1 to chr_count)
    for job_id in $(seq 1 $chr_count); do
        echo "Processing job_id: $job_id"
        run_command "python unify_bowtie.py \"$output_dir/kmers/k$k\" \"$output_dir/chrsize.tsv\" -job_id \"$job_id\"" "$log_file" "$err_file" &
    done
    wait  # Wait for all parallel jobs to finish
done

# 8. Move files
echo "8/9.Moving files..."
for k in "${kmer_array[@]}"; do
    echo "kmer: $k"
    source_dir="$output_dir/kmers/k$k"
    target_dir="$source_dir/TEMPs"

    # Check if the source directory exists
    if [ ! -d "$source_dir" ]; then
        echo "Error: Source directory not found: $source_dir"
        continue  # Skip to the next k-mer
    fi

    # Move files matching the pattern *kmer* to the target directory
    if ! mv "$source_dir"/*kmer* "$target_dir" 2>/dev/null; then
        echo "No files matching *kmer* found in $source_dir."
    else
        echo "Moved *kmer* files to $target_dir."
    fi
done

# 9. Combine umaps
echo "9/9.Run combine_umap"
for job_id in $(seq 1 $chr_count); do
    echo "Processing job_id: $job_id"
    run_command "python combine_umaps.py \"$output_dir/kmers\" \"$output_dir/chrsize.tsv\" -job_id \"$job_id\"" "$log_dir/combine_umaps.log" "$log_dir/combine_umaps.err" &
done
wait

echo "Finish"
