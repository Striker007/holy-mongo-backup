#!/usr/bin/env bash
# -*- mode: shell -*-
# vi: set ft=shell :

# CONFIGUTATION
export LC_ALL=en_US.UTF-8
set -uo pipefail
LOG=./dumped.log
AWS_BUCKET=dbdump
# AWS_SNS_ARN=""


# ./dump_mongodb myDb collPartOfName 10 /data/dump
#                  \         |       |    |
DB=$1  #___________/         |       |    |
FILTER=$2   #________________/       |    |
MAX_THREADS=$3 #_____________________/    |
OUT_DIR=$4  #_____________________________/

if [ -z "$DB" ]; then
    echo "err: put 1st param, database name"
    exit 1
fi

if [ -z "$FILTER" ]; then
    echo "err: put 2nd param, filter word for search collections"
    exit 1
fi

if [ -z "$MAX_THREADS" ]; then
    echo "err: put 3rd param, num parallel backups"
    exit 1
fi

if [ -z "$OUT_DIR" ]; then
    echo "err: put 4st param, dump directory"
    exit 1
fi


init_dirs()
{
    if [ ! -z "$1" -a ! -z "$2" ]; then
        local FILTER="$1"
        local OUT_DIR="$2"
        # TODO set global Log file path
        LOG_FILE=$(pwd)/${OUT_DIR}/${LOG}
        # get only date (digits) from filter
        # TODO refactor this
        local FILTER_DIR=`echo ${FILTER} | sed -n 's/_*[[:alpha:]]*_*\([0-9]*\)/\1/p'`
        mkdir -p ${OUT_DIR}/${FILTER_DIR}
    fi
}


log_write()
{
    echo ${1} >> ${LOG_FILE}
}


threads_count_runned()
{
    # TODO f**k if it works
    echo `ps ax | grep mongodump | grep db | grep -v grep |  wc -l`
}


control_concurrency()
{
    local threads=$(threads_count_runned)

    if [ -z "$(threads_count_runned)" ]; then
        threads=0
    else
        if [ ${threads} -ge ${MAX_THREADS} ]; then
            while [[ $(threads_count_runned) -ge ${MAX_THREADS} ]]; do
                sleep 1;
            done
        fi
    fi
}


get_collections()
{
    if [ ! -z "$1" ]; then
        local FILTER="$1"
        echo `echo 'show collections' | mongo ${DB} | grep ${FILTER}`
    fi
}


mongo_dump()
{
    if [ ! -z "$1" ]; then
        local FILTER="$1"
        local FILTER_DIR=`echo ${FILTER} | sed -n 's/_*[[:alpha:]]*_*\([0-9]*\)/\1/p'`
        local COLLECTIONS_LIST=$(get_collections ${FILTER})
        for COLLECTION in ${COLLECTIONS_LIST}; do
            echo ${COLLECTION} ' dumping'
            control_concurrency

            mongodump --db ${DB} --collection ${COLLECTION} --out ${OUT_DIR}/${FILTER_DIR} 2>&1 | tee -a ${LOG_FILE} &
        done;
    fi
}


mongo_zip_and_drop()
{
    if [ ! -z "$1" -a ! -z "$2" ]; then
        local FILTER="$1"
        local OUT_DIR="$2"
        local FILTER_DIR=`echo ${FILTER} | sed -n 's/_*[[:alpha:]]*_*\([0-9]*\)/\1/p'`

        cd ${OUT_DIR}
        # TODO del global var LOG_FILE  =\
        tar cvzf ${FILTER_DIR}.tar.gz ${FILTER_DIR} 2>&1 | tee -a ${LOG_FILE}
        if [ -n ${FILTER_DIR}.tar.gz ]; then
            rm -rf ${FILTER_DIR}
        fi
        cd -
    fi
}


mongo_upload_s3()
{
    if [ ! -z "$1" -a ! -z "$2" ]; then
        local FILTER="$1"
        local OUT_DIR="$2"
        local FILTER_DIR=`echo ${FILTER} | sed -n 's/_*[[:alpha:]]*_*\([0-9]*\)/\1/p'`
        cd ${OUT_DIR}
        # TODO del global var LOG_FILE  =\
        aws s3 cp ${FILTER_DIR}.tar.gz s3://${AWS_BUCKET}/ 2>&1 | tee -a ${LOG_FILE} && rm ${FILTER_DIR}.tar.gz
        log_write "DONE"
        # aws sns publish --subject "Mongo StatsDB from ${DUMP_DATE} is dumped" --topic-arn "${AWS_SNS_ARN}" --message file://${LOG_FILE}
        cd -
    fi
}


run()
{
    "$@"
}


run init_dirs ${FILTER} ${OUT_DIR}
run log_write "Begin dump at `date '+%Y-%m-%d %H:%m:%S'`"
run mongo_dump ${FILTER}
wait

run mongo_zip_and_drop ${FILTER} ${OUT_DIR}
run mongo_upload_s3 ${FILTER} ${OUT_DIR}
wait

exit 0
