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
        respond(404, [
            'success' => false,
            'event_code' => $eventCode,
            'exists' => false,
        ]);
    }

    respond(200, [
        'success' => true,
        'event_code' => $eventCode,
        'exists' => true,
        'event' => $event,
    ]);
} catch (Throwable $e) {
    respond(500, [
        'error' => 'Failed to fetch event',
        'details' => $e->getMessage(),
    ]);
}