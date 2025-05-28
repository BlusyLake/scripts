#!/bin/bash

RETENTION_DAYS=7
TMP_DIR="/tmp/db_dumps"
TODAY=$(date +%Y%m%d)
ARCHIVE_NAME="dumps_${TODAY}.tar.gz"
mkdir -p "$TMP_DIR"

# Recebe via variável JSON (que será lida e interpretada no Semaphore)
IFS=';' read -r SRC_DB_HOST SRC_DB_PORT SRC_DB_USER SRC_DB_PASSWORD SRC_DB_NAME DST_DB_NAME <<< "$DATABASE_ENTRY"
DST_DB_HOST="$DST_DB_HOST"
DST_DB_PORT="$DST_DB_PORT"
DST_DB_USER="$DST_DB_USER"
DST_DB_PASSWORD="$DST_DB_PASSWORD"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DUMP_FILE="$TMP_DIR/${SRC_DB_NAME}_from_${SRC_DB_HOST}_${SRC_DB_PORT}_to_${DST_DB_NAME}_${TIMESTAMP}.sql"

echo "📤 Dumpando $SRC_DB_NAME de $SRC_DB_HOST:$SRC_DB_PORT..."
PGPASSWORD=$SRC_DB_PASSWORD pg_dump -U "$SRC_DB_USER" -h "$SRC_DB_HOST" -p "$SRC_DB_PORT" "$SRC_DB_NAME" --no-owner --no-acl > "$DUMP_FILE"

if [ $? -ne 0 ]; then
  echo "❌ Falha no dump de $SRC_DB_NAME de $SRC_DB_HOST"
  exit 1
fi

echo "🔄 Recriando banco $DST_DB_NAME no destino..."
PGPASSWORD=$DST_DB_PASSWORD psql -U "$DST_DB_USER" -h "$DST_DB_HOST" -p "$DST_DB_PORT" -d postgres -c "DROP DATABASE IF EXISTS \"$DST_DB_NAME\";"
PGPASSWORD=$DST_DB_PASSWORD psql -U "$DST_DB_USER" -h "$DST_DB_HOST" -p "$DST_DB_PORT" -d postgres -c "CREATE DATABASE \"$DST_DB_NAME\";"

echo "📥 Importando para $DST_DB_NAME..."
PGPASSWORD=$DST_DB_PASSWORD psql -U "$DST_DB_USER" -h "$DST_DB_HOST" -p "$DST_DB_PORT" -d "$DST_DB_NAME" -f "$DUMP_FILE"

echo "✅ Banco $SRC_DB_NAME transferido para $DST_DB_NAME com sucesso!"

cd "$TMP_DIR"
tar -czf "$ARCHIVE_NAME" *.sql
rm -f "$TMP_DIR"/*.sql
find "$TMP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

echo "✅ Backup finalizado. Arquivo: $TMP_DIR/$ARCHIVE_NAME"
