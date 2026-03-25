<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method !== 'GET') {
    respond(405, ['error' => 'Method not allowed']);
}

$eventCode = sanitize_event_code((string)(get_query_param('id') ?? ''));

if ($eventCode === '') {
    respond(400, ['error' => 'Missing or invalid id']);
}

try {
    $event = $database->getEvent($eventCode);

    if ($event === null) {
        respond(404, ['error' => 'Event not found']);
    }

    if (empty($event['gallery_released'])) {
        respond(403, ['error' => 'Gallery not released']);
    }

    $galleryData = $database->getGallery($eventCode);

    if ($galleryData === null) {
        respond(200, [
            'event' => $event['event_name'],
            'start' => $event['event_start'],
            'end' => $event['event_end'],
            'hosts' => $event['host_names'],
            'gallery' => [],
        ]);
    }

    $gallery = [];

    foreach ((array)($galleryData['gallery'] ?? []) as $item) {
        if (!is_array($item)) {
            continue;
        }

        $id = sanitize_uuid((string)($item['id'] ?? ''));
        $storageKey = (string)($item['storage_key'] ?? '');

        if ($id === '' || $storageKey === '') {
            continue;
        }

        $extension = extension_from_storage_key($storageKey);

        $gallery[] = [
            'url' => $storage->getPublicUrl($storageKey),
            'guest' => [
                'id' => (string)($item['guest']['id'] ?? ''),
                'name' => (string)($item['guest']['name'] ?? ''),
            ],
            'taken' => $item['taken'] ?? null,
            'type' => $item['type'] ?? null,
            'file' => format_display_file($id, $extension),
        ];
    }

    respond(200, [
        'event' => $event['event_name'],
        'start' => $event['event_start'],
        'end' => $event['event_end'],
        'hosts' => $event['host_names'],
        'gallery' => $gallery,
    ]);

} catch (Throwable $e) {
    respond(500, [
        'error' => 'Failed to fetch gallery',
        'details' => $e->getMessage(),
    ]);
}

/*
|--------------------------------------------------------------------------
| Helper
|--------------------------------------------------------------------------
*/
function extension_from_storage_key(string $storageKey): string
{
    $path = parse_url($storageKey, PHP_URL_PATH);
    $path = is_string($path) ? $path : $storageKey;

    $extension = pathinfo($path, PATHINFO_EXTENSION);

    return is_string($extension) && $extension !== '' ? strtolower($extension) : 'bin';
}