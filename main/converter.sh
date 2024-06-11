#!/bin/bash

# get a list of files from the s3 bucket, and save them to a file,
# or use argument to specify a list of files to download
if [ ! -d ~/raw_metadata_csvs ]; then
        cd ~
        mkdir raw_metadata_csvs
        cd -
fi
if [ ! -d ~/converted_metadata_pickles ]; then
        cd ~
        mkdir converted_metadata_pickles
        cd -
fi
local_destination=~/raw_metadata_csvs
echo "set up dirs"

S3_RAW_METADATA_DIR=s3://serratus-biosamples/bioprojects_csv/
S3_CONDENSED_METADATA_DIR=s3://serratus-biosamples/condensed-bioproject-metadata/

if [ "$1" == "-s" ]; then
    if [ "$2" ]; then
        subset_size=$2
    else
        subset=10
    fi

    # remove files if they exist
    if [ -f file_list_with_sizes.txt ]; then
        rm file_list_with_sizes.txt
    fi
    touch file_list_with_sizes.txt
    size_list_file=file_list_with_sizes.txt
    if [ -f cp_batch_command_list.txt ]; then
        rm cp_batch_command_list.txt
    fi
    touch cp_batch_command_list.txt
    cp_file_name=cp_batch_command_list.txt
    if [ -f csv_files_list.txt ]; then
        rm csv_files_list.txt
    fi
    touch csv_files_list.txt
    disk_files_name=csv_files_list.txt

    s5cmd ls ${S3_RAW_METADATA_DIR} | awk '{print $NF, $(NF-1)}' | head -n ${subset_size} > ${size_list_file}
    echo "completed getting file list via s5cmd ls"

    while read -r line; do
        file=$(echo ${line} | awk '{print $(NF-1)}')
        echo "cp -f ${S3_RAW_METADATA_DIR}${file} ${local_destination}" >> ${cp_file_name}
        echo "${local_destination}/${file}" >> ${disk_files_name}
    done < ${size_list_file}

    echo "completed creating cp batch command list"

    s5cmd run ${cp_file_name}
    echo "completed copying raw csv files from s3 to local disk"

    time python3 converter_.py ${disk_files_name} ~/converted_metadata_pickles > log.txt
    echo "completed converting csv files to pickle files of condensed metadata"

    # sync the converted_metadata_pickles with an s3 bucket called s3://serratus-biosamples/condensed-bioproject-metadata/
    s5cmd sync ~/converted_metadata_pickles/ ${S3_CONDENSED_METADATA_DIR}
    echo "completed syncing pickle files to s3"

    rm ${cp_file_name}
    rm ${disk_files_name}

elif [ "$1" == "-f" ]; then
    s5cmd sync ${S3_RAW_METADATA_DIR}/ ${local_destination}
    echo "completed copying raw csv files from s3 to local disk"

    # time python3 converter_.py ${local_destination} ~/converted_metadata_pickles > log.txt
    time parallel -j 4 python3 converter_.py ::: ${local_destination} ::: ~/converted_metadata_pickles > log.txt
    echo "completed converting csv files to pickle files of condensed metadata"

    s5cmd sync ~/converted_metadata_pickles/ ${S3_CONDENSED_METADATA_DIR}
    echo "completed syncing pickle files to s3"
else
    echo "Please specify either -s for subset or -f for full"
fi

# nohup time python3 converter_.py ~/raw_metadata_csvs ~/converted_metadata_pickles > log.txt 2>&1 &
# time python3 converter_.py ~/raw_metadata_csvs ~/converted_metadata_pickles
