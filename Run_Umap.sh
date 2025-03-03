#!/usr/bin/env bash

# Enhanced error handling and safety settings
set -eo pipefail
shopt -s nullglob

show_usage() {
    echo "Genome Mappability Analysis Pipeline"
    echo "Usage:   $(basename "$0") <input_dir> <genome_file> <kmer_list> [-t threads]"
    echo "Example: $(basename "$0") data genome.fa '24 36 50 100' -t 16"
    echo ""
    echo "Parameters:"
    echo "  <input_dir>    Directory containing input files"
    echo "  <genome_file>  Reference genome in FASTA format"
    echo "  <kmer_list>    Space-separated list of k-mer lengths"
    echo "  -t <threads>    Number of threads to use (default: 16)"
}

# Parse command-line arguments
parse_arguments() {
    # Default thread count
    local threads=16

    while getopts "t:" opt; do
        case "$opt" in
            t)
                threads="$OPTARG"
                ;;
            *)
                show_usage
                exit 1
                ;;
        esac
    done

    shift $((OPTIND - 1))  # Move past the processed options

    # Capture positional parameters
    local input_dir="$1"
    local genome_file="$2"
    local kmer_list="$3"

    # Validate arguments
    validate_arguments "$input_dir" "$genome_file" "$kmer_list"

    # Return the parsed arguments as a space-separated string
    echo "$input_dir" "$genome_file" "$kmer_list" "$threads"
}

validate_arguments() {
    if [[ $# -lt 3 ]]; then
        >&2 echo "Error: Missing required arguments"
        show_usage
        exit 1
    fi

    if [[ ! -d "$1" ]]; then
        >&2 echo "Error: Input directory '$1' not found"
        exit 1
    fi

    local genome_path="$1/$2"
    if [[ ! -f "$genome_path" && ! -f "${genome_path}.gz" ]]; then
        >&2 echo "Error: Genome file '$2' not found in input directory"
        exit 1
    fi
}

execute_parallel() {
    local cmd_template=$1
    local max_jobs=$2
    local max_items=$3
    local -a pids=()
    local counter=1

    while [[ $counter -le $max_items ]]; do
        local current_cmd=$(printf "$cmd_template" "$counter")
        eval "$current_cmd" &
        pids+=($!)

        if [[ $(jobs -r -p | wc -l) -ge $max_jobs ]]; then
            wait -n
        fi
        
        ((counter++))
    done

    wait "${pids[@]}"
}

process_genome() {
    local input_dir=$1
    local genome_file=$2
    local output_dir=$3

    if [[ -f "${input_dir}/${genome_file}.gz" ]]; then
        gunzip -k "${input_dir}/${genome_file}.gz"
    fi

    samtools faidx "${input_dir}/${genome_file}"
    cut -f1,2 "${input_dir}/${genome_file}.fai" > "${output_dir}/chrom.sizes"
}

main() {
    # Initialize parameters
    local input_dir="$1"
    local genome_file="$2"
    local kmer_values=($3)
    local genome_name="${genome_file%.fa}"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local max_threads="$4"  # Threads count

    # Configuration settings
    local bowtie_path=$(command -v bowtie)
    local bowtie_dir="${bowtie_path%/bowtie}"
    local output_dir="${input_dir}/mappability_${genome_name}_${timestamp}"
    local log_dir="${output_dir}/logs"

    # Create directory structure
    mkdir -p "${output_dir}/"{genome,kmers,temp}
    mkdir -p "${log_dir}"

    # Process genome data
    echo "[1/7] Processing genome files..."
    process_genome "$input_dir" "$genome_file" "$output_dir"

    # Generate analysis scripts
    echo "[2/7] Generating analysis scripts..."
    python ubismap.py "${input_dir}/${genome_file}" \
        "${output_dir}/chrom.sizes" \
        "$output_dir" \
        "all.q" \
        "${bowtie_dir}/bowtie-build" \
        --kmer "${kmer_values[*]}" \
        -write_script "${output_dir}/analysis_script.sh"

    # Build Bowtie index
    echo "[3/7] Creating Bowtie index..."
    if ! compgen -G "${output_dir}/genome/Umap_bowtie.ind.*.ebwt" > /dev/null; then
        bowtie-build "${output_dir}/genome/genome.fa" \
            "${output_dir}/genome/Umap_bowtie.ind" \
            > "${log_dir}/bowtie_index.log" 2>&1
    fi

    # Process each kmer value
    for k in "${kmer_values[@]}"; do
        echo "[4/7-$k] Processing k=${k}..."

        local cmd_template="python get_kmers.py ${output_dir}/chrom.sizes \
            ${output_dir}/kmers/k${k} ${output_dir}/chrs \
            ${output_dir}/chrsize_index.tsv -job_id %s --kmer k${k} \
            > ${log_dir}/kmer_${k}_%s.log 2>&1"
        
        execute_parallel "$cmd_template" "$max_threads" \
            $(tail -1 "${output_dir}/chrsize_index.tsv" | awk '{print $1}')

        # Run Bowtie alignment
        echo "[5/7-$k] Performing alignments..."
        cmd_template="python run_bowtie.py ${output_dir}/kmers/k${k} ${bowtie_dir} \
            ${output_dir}/genome Umap_bowtie.ind -job_id %s \
            > ${log_dir}/align_${k}_%s.log 2>&1"
        
        execute_parallel "$cmd_template" "$max_threads" \
            $(tail -1 "${output_dir}/chrsize_index.tsv" | awk '{print $1}')

        # Combine results
        echo "[6/7-$k] Merging results..."
        cmd_template="python combine_umaps.py ${output_dir}/kmers \
            ${output_dir}/chrom.sizes -job_id %s \
            > ${log_dir}/merge_${k}_%s.log 2>&1"
        
        execute_parallel "$cmd_template" "$max_threads" \
            $(tail -1 "${output_dir}/chrsize_index.tsv" | awk '{print $1}')
    done

    # Cleanup temporary files
    echo "[7/7] Finalizing results..."
    find "${output_dir}" -name "*.tmp" -delete
    rm -f "${output_dir}/analysis_script.sh"

    echo "Analysis completed successfully. Results saved to: ${output_dir}"
}

# Main execution flow
parsed_args=$(parse_arguments "$@")
input_dir=$(echo "$parsed_args" | awk '{print $1}')
genome_file=$(echo "$parsed_args" | awk '{print $2}')
kmer_list=$(echo "$parsed_args" | awk '{print $3}')
threads=$(echo "$parsed_args" | awk '{print $4}')

main "$input_dir" "$genome_file" "$kmer_list" "$threads"