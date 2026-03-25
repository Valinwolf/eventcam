#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config.php"
SQL_FILE="$PROJECT_ROOT/setup/postgres.sql"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config.php not found at: $CONFIG_FILE"
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "ERROR: SQL file not found at: $SQL_FILE"
  exit 1
fi

echo "Reading database config from $CONFIG_FILE ..."

readarray -t DB_CONFIG < <(
php <<PHP
<?php
$config = require '$CONFIG_FILE';

if (!is_array($config)) {
    fwrite(STDERR, "config.php did not return an array\n");
    exit(1);
}

$params = $config['database_params'] ?? null;
if (!is_array($params)) {
    fwrite(STDERR, "Missing database_params in config.php\n");
    exit(1);
}

$driver = (string)($config['database_driver'] ?? '');
$dbname = (string)($params['dbname'] ?? '');
$user   = (string)($params['user'] ?? '');
$pass   = (string)($params['password'] ?? '');
$host   = (string)($params['host'] ?? '127.0.0.1');
$port   = (string)($params['port'] ?? '5432');
$schema = (string)($params['schema'] ?? 'public');

if ($driver === '') {
    fwrite(STDERR, "Missing database_driver in config.php\n");
    exit(1);
}
if ($dbname === '') {
    fwrite(STDERR, "Missing database_params.dbname in config.php\n");
    exit(1);
}
if ($user === '') {
    fwrite(STDERR, "Missing database_params.user in config.php\n");
    exit(1);
}

echo $driver, PHP_EOL;
echo $dbname, PHP_EOL;
echo $user, PHP_EOL;
echo $pass, PHP_EOL;
echo $host, PHP_EOL;
echo $port, PHP_EOL;
echo $schema, PHP_EOL;
PHP
)

DB_DRIVER="${DB_CONFIG[0]}"
DB_NAME="${DB_CONFIG[1]}"
DB_USER="${DB_CONFIG[2]}"
DB_PASS="${DB_CONFIG[3]}"
DB_HOST="${DB_CONFIG[4]}"
DB_PORT="${DB_CONFIG[5]}"
DB_SCHEMA="${DB_CONFIG[6]}"

if [[ "$DB_DRIVER" != "Postgres" ]]; then
  echo "ERROR: This setup script supports only database_driver=Postgres"
  exit 1
fi

echo "Starting EventCam PostgreSQL setup..."
echo "Driver : $DB_DRIVER"
echo "DB     : $DB_NAME"
echo "User   : $DB_USER"
echo "Host   : $DB_HOST"
echo "Port   : $DB_PORT"
echo "Schema : $DB_SCHEMA"

echo "Creating user if needed..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER'
   ) THEN
      CREATE ROLE "$DB_USER" LOGIN PASSWORD '$DB_PASS';
   ELSE
      ALTER ROLE "$DB_USER" WITH LOGIN PASSWORD '$DB_PASS';
   END IF;
END
\$\$;
EOF

echo "Creating database if needed..."
DB_EXISTS="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'")"
if [[ "$DB_EXISTS" != "1" ]]; then
  sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
fi

echo "Granting database privileges..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF
GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER";
EOF

echo "Applying schema from $SQL_FILE ..."
PGPASSWORD="$DB_PASS" psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -f "$SQL_FILE"

echo "Granting schema/table/sequence/function privileges..."
PGPASSWORD="$DB_PASS" psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -v ON_ERROR_STOP=1 <<EOF
GRANT USAGE, CREATE ON SCHEMA "$DB_SCHEMA" TO "$DB_USER";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA "$DB_SCHEMA" TO "$DB_USER";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA "$DB_SCHEMA" TO "$DB_USER";
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA "$DB_SCHEMA" TO "$DB_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA "$DB_SCHEMA"
GRANT ALL PRIVILEGES ON TABLES TO "$DB_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA "$DB_SCHEMA"
GRANT ALL PRIVILEGES ON SEQUENCES TO "$DB_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA "$DB_SCHEMA"
GRANT ALL PRIVILEGES ON FUNCTIONS TO "$DB_USER";
EOF

echo "EventCam PostgreSQL setup complete."