#!/usr/bin/env bash

TIME=$(date +%b-%d-%y-%H%M)
FILENAME="backup-$TIME.tar.gz"
TMP_DIR=/tmp

REPLACE=$(
  cat <<END
import sys
import re

for line in sys.stdin:
    line = re.sub(r'^\(', '', line)
    line = re.sub(r'\)$', '', line)
    sys.stdout.write(line)
END
)

# Convert ENV array into bash array
IGNORED_DATABASES=$(echo $IGNORED_DATABASES | python -c "$REPLACE")
DATABASES=$(echo $DATABASES | python -c "$REPLACE")

IGNORED_DATABASE_NAMES=($IGNORED_DATABASES)
DATABASE_NAMES=($DATABASES)

if [[ -z $DATABASES ]]; then
  DATABASE_NAMES=()
fi

DATABASES_TOTAL=${#DATABASE_NAMES[@]}

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY

if [[ $DATABASES_TOTAL -eq 0 ]]; then
  DATABASE_NAMES=$(echo "show databases;" | mysql -h "$DB_HOST" -p"$DB_PASSWORD" -u "$DB_USER")
fi

for database in ${DATABASE_NAMES[@]}; do
  if [[ " ${IGNORED_DATABASE_NAMES[@]} " =~ " ${database} " ]]; then
    printf "$database ignored\n"
  else
    printf "Backing up $database\n"

    set echo off
    mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$database" >"$TMP_DIR/$database.sql"
    tar -cpzf "$TMP_DIR/$database-$FILENAME" "$TMP_DIR/$database.sql"
    set echo on

    printf "Uploading to S3...\n"
    aws s3 --endpoint-url="$S3_ENDPOINT_URL" cp "$TMP_DIR/$database-$FILENAME" "s3://$S3_BUCKET_NAME/$S3_FOLDER/$database-$FILENAME"
    printf "Uploaded to S3.\n"

    printf "Cleaning up...\n"
    rm -rf "$TMP_DIR/$database-$FILENAME"
    printf "Cleaned up.\n"
  fi
done
