#!/usr/bin/env bash
# -*- mode: shell -*-
# vi: set ft=shell :

if [ -z "$1" ]; then
    echo "err: put 1st param, filter word for search collections"
    exit 1
fi

if [ -z "$2" ]; then
    echo "err: put 2st param, num parallel backups"
    exit 1
fi

FILTER=$1
max_threads=$2
DB=holyDB
OUT_DIR=/data/mongo_dump_striker

LOG_FILE=${OUT_DIR}/logs/${FILTER}.log
COLLECTIONS_LIST=`echo 'show collections' | mongo ${DB} | grep ${FILTER}`

mkdir -p ${OUT_DIR}/logs
echo "Begin dump at `date '+%Y-%m-%d %H:%m:%S'`" > ${LOG_FILE}
echo "Begin dump at `date '+%Y-%m-%d %H:%m:%S'`" > ${LOG_FILE_SHORT}

mkdir -p ${OUT_DIR}/${FILTER}

current_threads_runned()
{
    # fuck if it works
    echo `ps ax | grep mongodump | grep db | grep -v grep |  wc -l`
}

threads=0
for COLLECTION in ${COLLECTIONS_LIST} ; do
    # detect if we fired max_threads in pool
    if [ $threads -ge $2 ]; then
      # detect for free place in pool
      while [[ $(current_threads_runned) -ge $max_threads ]]; do
          sleep 1;
      done
      threads=$(current_threads_runned)
  else
      # fired thread
      echo $COLLECTION ' dumped'
      mongodump --db ${DB} --collection ${COLLECTION} --out ${OUT_DIR}/${FILTER} 2>&1 | tee -a ${LOG_FILE} &
      threads=$((threads+1))
  fi
done
