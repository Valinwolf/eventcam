<?php
declare(strict_types=1);

$allowNonPostgres = in_array('--allow-non-postgres', $argv ?? [], true);
$forceLocalAuth = in_array('--force-local-auth', $argv ?? [], true);

$currentUser = function_exists('posix_geteuid') && function_exists('posix_getpwuid')
    ? (posix_getpwuid(posix_geteuid())['name'] ?? null)
    : getenv('USER');

if (!$allowNonPostgres && $currentUser !== 'postgres') {
    fwrite(STDERR, "ERROR: This script must be run as the 'postgres' user.\n");
    fwrite(STDERR, "Try: sudo -u postgres php setup/postgres.php\n");
    fwrite(STDERR, "Or override with: php setup/postgres.php --allow-non-postgres\n");
    exit(1);
}

$projectRoot = dirname(__DIR__);
$configFile = $projectRoot . '/config.php';
$sqlFile = __DIR__ . '/postgres.sql';

if (!is_file($configFile)) {
    fwrite(STDERR, "ERROR: config.php not found at: {$configFile}\n");
    exit(1);
}

if (!is_file($sqlFile)) {
    fwrite(STDERR, "ERROR: SQL file not found at: {$sqlFile}\n");
    exit(1);
}

echo "Reading database config from {$configFile} ...\n";

$config = require_once $configFile;

if (!is_array($config)) {
    fwrite(STDERR, "ERROR: config.php did not return an array\n");
    exit(1);
}

$driver = (string)($config['database_driver'] ?? '');
$params = $config['database_params'] ?? null;

if (!is_array($params)) {
    fwrite(STDERR, "ERROR: Missing database_params in config.php\n");
    exit(1);
}

$dbName = (string)($params['dbname'] ?? '');
$dbUser = (string)($params['user'] ?? '');
$dbPass = (string)($params['password'] ?? '');
$dbHost = (string)($params['host'] ?? '127.0.0.1');
$dbPort = (string)($params['port'] ?? '5432');
$dbSchema = (string)($params['schema'] ?? 'public');

if ($driver !== 'Postgres') {
    fwrite(STDERR, "ERROR: This setup script supports only database_driver=Postgres\n");
    exit(1);
}

if ($dbName === '') {
    fwrite(STDERR, "ERROR: Missing database_params.dbname in config.php\n");
    exit(1);
}

if ($dbUser === '') {
    fwrite(STDERR, "ERROR: Missing database_params.user in config.php\n");
    exit(1);
}

echo "Starting EventCam PostgreSQL setup...\n";
echo "Driver : {$driver}\n";
echo "DB     : {$dbName}\n";
echo "User   : {$dbUser}\n";
echo "Host   : {$dbHost}\n";
echo "Port   : {$dbPort}\n";
echo "Schema : {$dbSchema}\n";
echo "Admin  : " . ($forceLocalAuth ? "local/peer auth forced" : "automatic") . "\n";

function quoteIdent(string $value): string
{
    return '"' . str_replace('"', '""', $value) . '"';
}

function quoteLiteral(PDO $pdo, string $value): string
{
    $quoted = $pdo->quote($value);
    if ($quoted === false) {
        throw new DatabaseException("Failed to quote literal");
    }

    return $quoted;
}

function connectAsAdmin(string $dbHost, string $dbPort, bool $forceLocalAuth): PDO
{
    $candidates = [];

    if ($forceLocalAuth) {
        $candidates = [
            'pgsql:dbname=postgres',
            'pgsql:host=/var/run/postgresql;dbname=postgres',
            'pgsql:host=/run/postgresql;dbname=postgres',
        ];
    } else {
        $candidates = [
            sprintf('pgsql:host=%s;port=%s;dbname=postgres', $dbHost, $dbPort),
            'pgsql:dbname=postgres',
            'pgsql:host=/var/run/postgresql;dbname=postgres',
            'pgsql:host=/run/postgresql;dbname=postgres',
        ];
    }

    $lastError = null;

    foreach ($candidates as $dsn) {
        try {
            return new PDO($dsn, 'postgres', null, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
        } catch (Throwable $e) {
            $lastError = $e;
        }
    }

    $message = $forceLocalAuth
        ? "Failed to connect as postgres user using local/peer auth."
        : "Failed to connect as postgres user.";

    if ($lastError !== null) {
        $message .= " DETAILS: " . $lastError->getMessage();
    }

    throw new DatabaseException($message);
}

try {
    $pdo = connectAsAdmin($dbHost, $dbPort, $forceLocalAuth);
} catch (Throwable $e) {
    fwrite(STDERR, "ERROR: {$e->getMessage()}\n");
    if ($forceLocalAuth) {
        fwrite(STDERR, "Make sure peer/local auth is enabled for the postgres role.\n");
    } else {
        fwrite(STDERR, "Run as postgres or use --force-local-auth if your server is configured for peer auth.\n");
    }
    exit(1);
}

try {
    echo "Creating user if needed...\n";

    $stmt = $pdo->prepare('SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = :name');
    $stmt->execute(['name' => $dbUser]);
    $roleExists = (bool)$stmt->fetchColumn();

    $quotedUserIdent = quoteIdent($dbUser);
    $quotedPassword = quoteLiteral($pdo, $dbPass);

    if (!$roleExists) {
        $pdo->exec("CREATE ROLE {$quotedUserIdent} LOGIN PASSWORD {$quotedPassword}");
    } else {
        $pdo->exec("ALTER ROLE {$quotedUserIdent} WITH LOGIN PASSWORD {$quotedPassword}");
    }

    echo "Creating database if needed...\n";

    $stmt = $pdo->prepare('SELECT 1 FROM pg_database WHERE datname = :name');
    $stmt->execute(['name' => $dbName]);
    $dbExists = (bool)$stmt->fetchColumn();

    $quotedDbIdent = quoteIdent($dbName);

    if (!$dbExists) {
        $pdo->exec("CREATE DATABASE {$quotedDbIdent} OWNER {$quotedUserIdent}");
    }

    echo "Granting database privileges...\n";
    $pdo->exec("GRANT ALL PRIVILEGES ON DATABASE {$quotedDbIdent} TO {$quotedUserIdent}");

    echo "Applying schema from {$sqlFile} ...\n";

    $dbDsn = sprintf('pgsql:host=%s;port=%s;dbname=%s', $dbHost, $dbPort, $dbName);
    $dbPdo = new PDO($dbDsn, $dbUser, $dbPass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);

    $sql = file_get_contents($sqlFile);
    if ($sql === false) {
        throw new DatabaseException("Failed to read SQL file");
    }

    $dbPdo->exec($sql);

    echo "Granting schema/table/sequence/function privileges...\n";

    $quotedSchemaIdent = quoteIdent($dbSchema);

    $dbPdo->exec("GRANT USAGE, CREATE ON SCHEMA {$quotedSchemaIdent} TO {$quotedUserIdent}");
    $dbPdo->exec("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA {$quotedSchemaIdent} TO {$quotedUserIdent}");
    $dbPdo->exec("GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA {$quotedSchemaIdent} TO {$quotedUserIdent}");
    $dbPdo->exec("GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA {$quotedSchemaIdent} TO {$quotedUserIdent}");

    $dbPdo->exec("ALTER DEFAULT PRIVILEGES IN SCHEMA {$quotedSchemaIdent} GRANT ALL PRIVILEGES ON TABLES TO {$quotedUserIdent}");
    $dbPdo->exec("ALTER DEFAULT PRIVILEGES IN SCHEMA {$quotedSchemaIdent} GRANT ALL PRIVILEGES ON SEQUENCES TO {$quotedUserIdent}");
    $dbPdo->exec("ALTER DEFAULT PRIVILEGES IN SCHEMA {$quotedSchemaIdent} GRANT ALL PRIVILEGES ON FUNCTIONS TO {$quotedUserIdent}");

    echo "EventCam PostgreSQL setup complete.\n";
    exit(0);
} catch (Throwable $e) {
    fwrite(STDERR, "ERROR: {$e->getMessage()}\n");
    exit(1);
}