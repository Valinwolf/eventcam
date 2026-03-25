<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

switch ($method) {
    case 'PUT':
        handle_put_guest();
        break;

    case 'GET':
        handle_get_guest();
        break;

    default:
        respond(405, ['error' => 'Method not allowed']);
}

/*
|--------------------------------------------------------------------------
| PUT /api/guest
|--------------------------------------------------------------------------
| Create a new guest
*/
function handle_put_guest(): void
{
    global $database;

    $body = get_json_body();

    $name = sanitize_name((string)($body['name'] ?? ''));

    if ($name === '') {
        respond(400, ['error' => 'Missing or invalid name']);
    }

    try {
        $guest = $database->putGuest($name);

        respond(200, [
            'id' => $guest['id'],
            'name' => $guest['name'],
        ]);
    } catch (Throwable $e) {
        respond(500, [
            'error' => 'Failed to create guest',
            'details' => $e->getMessage(),
        ]);
    }
}

/*
|--------------------------------------------------------------------------
| GET /api/guest
|--------------------------------------------------------------------------
| List guests for event
*/
function handle_get_guest(): void
{
    global $database;

    $eventCode = sanitize_event_code((string)(get_query_param('event_code') ?? ''));

    if ($eventCode === '') {
        respond(400, ['error' => 'Missing or invalid event_code']);
    }

    $event = $database->getEvent($eventCode);

    if ($event === null) {
        respond(404, ['error' => 'Event not found']);
    }

    try {
        $guests = $database->getGuestsByEvent($eventCode);

        respond(200, [
            'event_code' => $eventCode,
            'guests' => $guests,
        ]);
    } catch (Throwable $e) {
        respond(500, [
            'error' => 'Failed to fetch guests',
            'details' => $e->getMessage(),
        ]);
    }
}