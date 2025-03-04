# Clone this project.
$ git clone https://github.com/Cas660/Blacklist

# 1.Install Umap(version 1.2.1) and generate the reference genome mappability data. 
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
$ mkdir mappability_data<br>
$ cd mappability_data
## step4：Download the reference genome files.
To ensure that the final generated genome blacklist is in the format "chr15 62500 107500 Low Mappability", the first line of the genome file should start with something like >chr1.
Here, I recommend that you download the reference genome files from the [UCSC Genome Browser](https://genome.ucsc.edu/cgi-bin/hgGateway). <br>
e.g. $ rsync -avzP rsync://hgdownload.soe.ucsc.edu/goldenPath/danRer11/bigZips/danRer11.fa.gz .
