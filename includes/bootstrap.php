<?php
declare(strict_types=1);

header('Content-Type: application/json');

require_once __DIR__ . '/exceptions.php';
require_once __DIR__ . '/database.php';
require_once __DIR__ . '/storage.php';

/*
|--------------------------------------------------------------------------
| Response Helper
|--------------------------------------------------------------------------
*/
function respond(int $status, array $data = []): void
{
    http_response_code($status);

    if (!empty($data)) {
        echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    }

    exit;
}

/*
|--------------------------------------------------------------------------
| Request Helpers
|--------------------------------------------------------------------------
*/
function get_json_body(): array
{
    $raw = file_get_contents('php://input');

    if ($raw === false || $raw === '') {
        return [];
    }

    $decoded = json_decode($raw, true);

    if (!is_array($decoded)) {
        respond(400, ['error' => 'Invalid JSON body']);
    }

    return $decoded;
}

function get_query_param(string $key): ?string
{
    if (!isset($_GET[$key])) {
        return null;
    }

    $value = $_GET[$key];

    if (!is_scalar($value)) {
        return null;
    }

    return trim((string)$value);
}

/*
|--------------------------------------------------------------------------
| Validation Helpers
|--------------------------------------------------------------------------
*/
function sanitize_event_code(string $value): string
{
    $value = trim($value);
    return preg_replace('/[^A-Za-z0-9_-]/', '', $value) ?? '';
}

function sanitize_uuid(string $value): string
{
    $value = trim($value);

    if (!preg_match('/^[a-f0-9-]{36}$/i', $value)) {
        return '';
    }

    return strtolower($value);
}

function sanitize_name(string $value): string
{
    $value = trim($value);
    $value = preg_replace('/[<>:"\/\\\\|?*\x00-\x1F]/u', '', $value) ?? '';
    $value = preg_replace('/\s+/u', ' ', $value) ?? '';
    return trim($value);
}

/*
|--------------------------------------------------------------------------
| Utility Helpers
|--------------------------------------------------------------------------
*/
function format_display_file(string $uuid, string $extension): string
{
    $clean = str_replace('-', '', strtolower($uuid));

    $first = substr($clean, 0, 3);
    $last = substr($clean, -4);

    return $first . '-' . $last . '.' . $extension;
}

/*
|--------------------------------------------------------------------------
| Bootstrap Config + Drivers
|--------------------------------------------------------------------------
*/
try {
    $config = require_once __DIR__ . '/../config.php';

    if (!is_array($config)) {
        throw new ConfigException('config.php must return an array');
    }

    /*
    |--------------------------------------------------------------------------
    | Validate Config
    |--------------------------------------------------------------------------
    */
    $storageDriverName = (string)($config['storage_driver'] ?? '');
    $storageParams = (array)($config['storage_params'] ?? []);

    $databaseDriverName = (string)($config['database_driver'] ?? '');
    $databaseParams = (array)($config['database_params'] ?? []);

    $allowedMimeTypes = (array)($config['allowed_mime_types'] ?? []);
    $maxFileSize = (int)($config['max_file_size'] ?? 0);

    if ($storageDriverName === '') {
        throw new ConfigException('Missing config: storage_driver');
    }

    if ($databaseDriverName === '') {
        throw new ConfigException('Missing config: database_driver');
    }

    if ($maxFileSize <= 0) {
        throw new ConfigException('Invalid config: max_file_size');
    }

    /*
    |--------------------------------------------------------------------------
    | Load Storage Driver
    |--------------------------------------------------------------------------
    */
    $storageDriverFile = __DIR__ . '/../extension/storage.' . strtolower($storageDriverName) . '.php';
    $storageDriverClass = 'Storage_' . $storageDriverName;

    if (!is_file($storageDriverFile)) {
        throw new DriverException('Storage driver file not found: ' . $storageDriverFile);
    }

    require_once $storageDriverFile;

    if (!class_exists($storageDriverClass)) {
        throw new DriverException('Storage driver class not found: ' . $storageDriverClass);
    }

    /** @var StorageDriver $storage */
    $storage = new $storageDriverClass($storageParams);

    /*
    |--------------------------------------------------------------------------
    | Load Database Driver
    |--------------------------------------------------------------------------
    */
    $databaseDriverFile = __DIR__ . '/../extension/database.' . strtolower($databaseDriverName) . '.php';
    $databaseDriverClass = 'Database_' . $databaseDriverName;

    if (!is_file($databaseDriverFile)) {
        throw new DriverException('Database driver file not found: ' . $databaseDriverFile);
    }

    require_once $databaseDriverFile;

    if (!class_exists($databaseDriverClass)) {
        throw new DriverException('Database driver class not found: ' . $databaseDriverClass);
    }

    $databaseParams['base_prefix'] = (string)($storageParams['base_prefix'] ?? 'uploads');

    /** @var DatabaseDriver $database */
    $database = new $databaseDriverClass($databaseParams);

} catch (Throwable $e) {
    respond(500, [
        'error' => 'Bootstrap failure',
        'message' => $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
    ]);
}