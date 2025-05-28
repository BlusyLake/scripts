#!/bin/bash

set -e

RETENTION_DAYS=7
TMP_DIR="/tmp/db_dumps"
TODAY=$(date +%Y%m%d)
ARCHIVE_NAME="dumps_${TODAY}.tar.gz"
mkdir -p "$TMP_DIR"

# Espera variável DATABASE_ENTRIES no formato:
# "host1;port1;user1;pass1;dborigem1;dbdestino1|host2;port2;user2;pass2;dborigem2;dbdestino2"
IFS='|' read -ra DATABASES <<< "$DATABASE_ENTRIES"

for entry in "${DATABASES[@]}"; do
  IFS=';' read -r SRC_DB_HOST SRC_DB_PORT SRC_DB_USER SRC_DB_PASSWORD SRC_DB_NAME DST_DB_NAME <<< "$entry"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  DUMP_FILE="$TMP_DIR/${SRC_DB_NAME}_from_${SRC_DB_HOST}_${SRC_DB_PORT}_to_${DST_DB_NAME}_${TIMESTAMP}.sql"

  echo "📤 Dumpando $SRC_DB_NAME de $SRC_DB_HOST:$SRC_DB_PORT..."
  PGPASSWORD="$SRC_DB_PASSWORD" pg_dump -U "$SRC_DB_USER" -h "$SRC_DB_HOST" -p "$SRC_DB_PORT" "$SRC_DB_NAME" --no-owner --no-acl > "$DUMP_FILE"

  echo "🔄 Recriando banco $DST_DB_NAME no destino..."
  PGPASSWORD="$DST_DB_PASSWORD" psql -U "$DST_DB_USER" -h "$DST_DB_HOST" -p "$DST_DB_PORT" -d postgres -c "DROP DATABASE IF EXISTS \"$DST_DB_NAME\";"
  PGPASSWORD="$DST_DB_PASSWORD" psql -U "$DST_DB_USER" -h "$DST_DB_HOST" -p "$DST_DB_PORT" -d postgres -c "CREATE DATABASE \"$DST_DB_NAME\";"

  echo "📥 Importando para $DST_DB_NAME..."
  PGPASSWORD="$DST_DB_PASSWORD" psql -U "$DST_DB_USER" -h "$DST_DB_HOST" -p "$DST_DB_PORT" -d "$DST_DB_NAME" -f "$DUMP_FILE"

  echo "✅ Banco $SRC_DB_NAME transferido para $DST_DB_NAME com sucesso!"
done

# Compactar os dumps
cd "$TMP_DIR"
echo "📦 Compactando os dumps em $ARCHIVE_NAME..."
tar -czf "$ARCHIVE_NAME" *.sql

# Limpar .sql
rm -f "$TMP_DIR"/*.sql

# Apagar arquivos antigos
find "$TMP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

# Copiar para destino final
if [ -n "$BACKUP_DEST_PATH" ]; then
  echo "📁 Movendo para $BACKUP_DEST_PATH"
  mkdir -p "$BACKUP_DEST_PATH"
  mv "$ARCHIVE_NAME" "$BACKUP_DEST_PATH/"
fi

echo "✅ Processo finalizado. Arquivo de backup: ${BACKUP_DEST_PATH}/${ARCHIVE_NAME}"
