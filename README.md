# 1.Clone this project.
$ git clone https://github.com/Cas660/Blacklist <br>
$ cd Blacklist
# 2. Generate the reference genome mappability data.
## step1: Use conda to create an independent environment (Python 2.7)
$ conda create -n Umap_env python=2.7 <br>
$ conda activate umap_env
## step2：Install Required Packages
$ conda install bowtie=1.2.3 <br>
$ pip install argparse numpy pandas <br>
$ conda install samtools=1.21 <br>
## step3：Install Umap version 1.2.1
Download version 1.2.1 of Umap from the [hoffmangroup/umap project](https://github.com/hoffmangroup/umap/tags)  and extract it. <br>
$ cd umap-1.2.1/umap <br>
$ mv ../../Run_Umap.sh ./ <br>
$ mkdir mappability_data<br>
$ cd mappability_data
## step4：Download the reference genome files.
To ensure that the final generated genome blacklist is in the format "chr15 62500 107500 Low Mappability", the first line of the genome file should start with something like >chr1.
Here, I recommend that you download the reference genome files from the [UCSC Genome Browser](https://genome.ucsc.edu/cgi-bin/hgGateway). <br>
e.g. $ rsync -avzP rsync://hgdownload.soe.ucsc.edu/goldenPath/danRer11/bigZips/danRer11.fa.gz . <br>
$ gunzip danRer11.fa.gz
$ cd ..
## step5：Generate genome mappability data
$ ./Run_Umap.sh mappability_data danRer11.fa.gz "24 36 50 75 100 150 200" -t 8<br>
This step takes a relatively long time to run, so you can let it run in the background.<br>
Usage: bash Run_Umap.sh <genome_file> <kmer_list> <br>

