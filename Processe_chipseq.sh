#!/bin/bash

# Set paths and parameters
REFERENCE_INDEX="/data/lumj/Homo/data/hs1_bowtie_index/hs1_genome_index"  # Path to Bowtie2 reference genome index (without suffix)
INPUT_DIR="/data/lumj/Homo/data/raw_fastq"                       # Directory containing raw FASTQ files
OUTPUT_DIR="/data/lumj/mouse/bowtie2_bamfile"                # Output directory
THREADS=8                                                   # Number of threads to use
ERROR_LOG="$OUTPUT_DIR/error_log.txt"                        # Log file for failed files
CHECKPOINT_FILE="$OUTPUT_DIR/checkpoint.txt"                 # Checkpoint file to track processed files

# Extract genome name from Bowtie2 index path
GENOME_NAME=$(basename $REFERENCE_INDEX)
GENOME_NAME=${GENOME_NAME%_index}

# Check if genome name extraction was successful
if [ -z "$GENOME_NAME" ]; then
    echo "ERROR: Failed to extract genome name from reference index path."
    exit 1
else
    echo "Genome name extracted: $GENOME_NAME"
fi

# Define log files
FASTP_LOG="$OUTPUT_DIR/fastp.log"
BOWTIE2_LOG="$OUTPUT_DIR/bowtie2_${GENOME_NAME}.log"

# Create output directories
mkdir -p $OUTPUT_DIR/fastp_cleaned
mkdir -p $OUTPUT_DIR/bowtie2_aligned
mkdir -p "$OUTPUT_DIR/sorted_bam/$GENOME_NAME"

# Initialize log files
> $BOWTIE2_LOG  
> $ERROR_LOG    
touch $CHECKPOINT_FILE

# Check input files
echo "Checking input files in $INPUT_DIR..."
if [ -z "$(ls -A $INPUT_DIR/*.fastq.gz 2>/dev/null)" ]; then
    echo "ERROR: No .fastq.gz files found in $INPUT_DIR."
    exit 1
else
    echo "Found the following .fastq.gz files:"
    ls $INPUT_DIR/*.fastq.gz
fi

# Check software dependencies
echo "Checking software dependencies..."
fastp --version || { echo "ERROR: fastp not found."; exit 1; }
bowtie2 --version || { echo "ERROR: bowtie2 not found."; exit 1; }
samtools --version || { echo "ERROR: samtools not found."; exit 1; }

# Process each FASTQ file
for FASTQ_FILE in $INPUT_DIR/*.fastq.gz; do
    BASENAME=$(basename $FASTQ_FILE .fastq.gz)

    # Check if the file has already been processed
    if grep -Fxq "$BASENAME" "$CHECKPOINT_FILE"; then
        echo "File $BASENAME already processed. Skipping..."
        continue
    fi

    # Define output file names
    CLEANED_FASTQ="$OUTPUT_DIR/fastp_cleaned/${BASENAME}_cleaned.fastq.gz"
    FASTP_JSON="$OUTPUT_DIR/fastp_cleaned/${BASENAME}_fastp.json"
    FASTP_HTML="$OUTPUT_DIR/fastp_cleaned/${BASENAME}_fastp.html"
    SAM_FILE="$OUTPUT_DIR/bowtie2_aligned/${BASENAME}.sam"
    BAM_FILE="$OUTPUT_DIR/bowtie2_aligned/${BASENAME}.bam"
    SORTED_BAM="$OUTPUT_DIR/sorted_bam/$GENOME_NAME/${BASENAME}.sorted.bam"
    BAI_FILE="$OUTPUT_DIR/sorted_bam/$GENOME_NAME/${BASENAME}.sorted.bam.bai"

    # Step 1: Perform quality control with fastp
    echo "Processing $FASTQ_FILE with fastp..."
    echo "===== Processing file: $BASENAME =====" >> $FASTP_LOG
    fastp -i $FASTQ_FILE \
          -o $CLEANED_FASTQ \
          -j $FASTP_JSON \
          -h $FASTP_HTML \
          --thread $THREADS >> $FASTP_LOG 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: fastp failed for $FASTQ_FILE. Skipping..."
        echo "$FASTQ_FILE" >> $ERROR_LOG
        continue
    fi

    # Step 2: Align reads with Bowtie2
    echo "Aligning $CLEANED_FASTQ with Bowtie2..."
    echo "===== Processing file: $BASENAME =====" >> $BOWTIE2_LOG
    bowtie2 -x $REFERENCE_INDEX \
            -U $CLEANED_FASTQ \
            -S $SAM_FILE \
            --threads $THREADS >> $BOWTIE2_LOG 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Bowtie2 failed for $CLEANED_FASTQ. Skipping..."
        echo "$FASTQ_FILE" >> $ERROR_LOG
        continue
    fi

    # Step 3: Convert SAM to BAM
    echo "Converting $SAM_FILE to BAM..."
    samtools view -bS $SAM_FILE -o $BAM_FILE
    if [ $? -ne 0 ]; then
        echo "ERROR: samtools view failed for $SAM_FILE. Skipping..."
        echo "$FASTQ_FILE" >> $ERROR_LOG
        continue
    fi

    # Step 4: Sort BAM file
    echo "Sorting $BAM_FILE..."
    samtools sort $BAM_FILE -o $SORTED_BAM -@ $THREADS
    if [ $? -ne 0 ]; then
        echo "ERROR: samtools sort failed for $BAM_FILE. Skipping..."
        echo "$FASTQ_FILE" >> $ERROR_LOG
        continue
    fi

    # Step 5: Index BAM file
    echo "Indexing $SORTED_BAM..."
    samtools index $SORTED_BAM $BAI_FILE
    if [ $? -ne 0 ]; then
        echo "ERROR: samtools index failed for $SORTED_BAM. Skipping..."
        echo "$FASTQ_FILE" >> $ERROR_LOG
        continue
    fi

    # Delete intermediate files to save space
    rm $SAM_FILE $BAM_FILE || { echo "WARNING: Failed to delete intermediate files for $BASENAME."; }

    # Record successfully processed file
    echo "$BASENAME" >> $CHECKPOINT_FILE
    echo "Finished processing $FASTQ_FILE. Sorted BAM file: $SORTED_BAM"
done

echo "All files processed!"
echo "Failed files are logged in $ERROR_LOG."
