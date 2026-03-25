<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';

const MISSING_INVALID_ID_ERROR = 'Missing or invalid id';
const EVENT_NOT_FOUND_ERROR = 'Event not found';

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

switch ($method) {
    case 'GET':
        handle_get_media();
        break;

    case 'PUT':
        handle_put_media();
        break;

    case 'PATCH':
        handle_patch_media();
        break;

    case 'DELETE':
        handle_delete_media();
        break;

    default:
        respond(405, ['error' => 'Method not allowed']);
}

function handle_get_media(): void
{
    global $database, $storage;

    $eventCode = sanitize_event_code((string)(get_query_param('event_code') ?? ''));
    $guestId = sanitize_uuid((string)(get_query_param('id') ?? ''));

    if ($eventCode === '') {
        respond(400, ['error' => 'Missing or invalid event_code']);
    }

    if ($guestId === '') {
        respond(400, ['error' => MISSING_INVALID_ID_ERROR]);
    }

    try {
        $event = $database->getEvent($eventCode);
        if ($event === null) {
            respond(404, ['error' => EVENT_NOT_FOUND_ERROR]);
        }

        $result = $database->getMediaByGuest($eventCode, $guestId);
        if ($result === null) {
            respond(404, ['error' => 'Guest not found for event']);
        }

        $media = [];
        foreach ((array)($result['media'] ?? []) as $item) {
            if (!is_array($item)) {
                continue;
            }

            $id = isset($item['id']) ? sanitize_uuid((string)$item['id']) : '';
            $storageKey = (string)($item['storage_key'] ?? '');
            $file = (string)($item['file'] ?? '');

            if ($id === '' || $storageKey === '') {
                continue;
            }

            if ($file === '') {
                $file = format_display_file($id, extension_from_storage_key($storageKey));
            }

            $media[] = [
                'id' => $id,
                'file' => $file,
                'url' => $storage->getPublicUrl($storageKey),
            ];
        }

        respond(200, [
            'guest' => [
                'id' => (string)($result['guest']['id'] ?? $guestId),
                'name' => (string)($result['guest']['name'] ?? ''),
            ],
            'media' => $media,
        ]);
    } catch (Throwable $e) {
        respond(500, [
            'error' => 'Failed to fetch media',
            'details' => $e->getMessage(),
        ]);
    }
}

function handle_put_media(): void
{
    global $database, $storage, $allowedMimeTypes;

    $body = get_json_body();

    $eventCode = sanitize_event_code((string)($body['event_code'] ?? ''));
    $guestId = sanitize_uuid((string)($body['guest_id'] ?? ''));
    $mime = trim((string)($body['mime'] ?? ''));

    if ($eventCode === '') {
        respond(400, ['error' => 'Missing or invalid event_code']);
    }

    if ($guestId === '') {
        respond(400, ['error' => 'Missing or invalid guest_id']);
    }

    if ($mime === '' || !isset($allowedMimeTypes[$mime])) {
        respond(400, [
            'error' => 'Unsupported or missing mime',
            'mime' => $mime,
        ]);
    }

    try {
        $event = $database->getEvent($eventCode);
        if ($event === null) {
            respond(404, ['error' => EVENT_NOT_FOUND_ERROR]);
        }

        $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));

        if (!empty($event['event_start'])) {
            $eventStart = new DateTimeImmutable((string)$event['event_start']);
            if ($now < $eventStart) {
                respond(403, ['error' => 'Event has not started']);
            }
        }

        if (!empty($event['event_end'])) {
            $eventEnd = new DateTimeImmutable((string)$event['event_end']);
            if ($now > $eventEnd) {
                respond(403, ['error' => 'Event has ended']);
            }
        }

        $extension = (string)$allowedMimeTypes[$mime];

        $media = $database->createMedia(
            $eventCode,
            $guestId,
            $mime,
            $extension
        );

        $uploadInstruction = $storage->createUploadInstruction(
            (string)$media['storage_key'],
            $mime
        );

        respond(200, [
            'id' => (string)$media['id'],
            'upload' => $uploadInstruction,
            'control_token' => $media['control_token'] ?? null,
        ]);
    } catch (Throwable $e) {
        $message = $e->getMessage();
        $status = 500;

        if ($message === EVENT_NOT_FOUND_ERROR) {
            $status = 404;
        } elseif (
            $message === 'Photo uploads are disabled for this event' ||
            $message === 'Video uploads are disabled for this event'
        ) {
            $status = 403;
        }

        respond($status, [
            'error' => 'Failed to create media',
            'details' => $message,
        ]);
    }
}

function handle_patch_media(): void
{
    global $database;

    $body = get_json_body();

    $id = sanitize_uuid((string)($body['id'] ?? $body['uuid'] ?? ''));
    $status = trim((string)($body['status'] ?? ''));
    $reason = isset($body['reason']) ? trim((string)$body['reason']) : null;

    if ($id === '') {
        respond(400, ['error' => MISSING_INVALID_ID_ERROR]);
    }

    if ($status === '') {
        respond(400, ['error' => 'Missing or invalid status']);
    }

    if (!in_array($status, ['uploaded', 'failed'], true)) {
        respond(400, ['error' => 'Unsupported status']);
    }

    try {
        $result = match ($status) {
            'uploaded' => $database->markMediaUploaded($id),
            'failed' => $database->markMediaFailed($id, $reason),
        };

        if ($result === null) {
            respond(404, ['error' => 'Media not found']);
        }

        respond(200);
    } catch (Throwable $e) {
        respond(500, [
            'error' => 'Failed to update media status',
            'details' => $e->getMessage(),
        ]);
    }
}

function handle_delete_media(): void
{
    global $database, $storage;

    $id = sanitize_uuid((string)(get_query_param('id') ?? ''));
    $token = trim((string)(get_query_param('token') ?? ''));

    if ($id === '') {
        respond(400, ['error' => 'Missing or invalid id']);
    }

    if ($token === '') {
        respond(400, ['error' => 'Missing or invalid token']);
    }

    try {
        $media = $database->getMediaById($id);
        if ($media === null) {
            respond(401, ['error' => 'Media/token pair never existed']);
        }

        $match = $database->findMediaForDelete($id, $token);
        if ($match === null) {
            respond(401, ['error' => 'Media/token pair never existed']);
        }

        if (!empty($match['deleted_at']) || (($match['status'] ?? '') === 'deleted')) {
            respond(410, ['error' => 'Media already deleted']);
        }

        if (!empty($match['control_token_expires_at'])) {
            $expiresAt = new DateTimeImmutable((string)$match['control_token_expires_at']);
            $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));

            if ($now > $expiresAt) {
                respond(403, ['error' => 'Control token expired']);
            }
        }

        $storageKey = (string)($match['storage_key'] ?? '');
        if ($storageKey !== '') {
            try {
                $storage->delete($storageKey);
            } catch (Throwable $e) {
                if (($match['status'] ?? '') === 'uploaded' || ($match['status'] ?? '') === 'pending') {
                    throw $e;
                }
            }
        }

        $deleted = $database->markMediaDeleted($id);
        if (!$deleted) {
            respond(500, ['error' => 'Failed to update media metadata']);
        }

        respond(200);
    } catch (Throwable $e) {
        respond(500, [
            'error' => 'Failed to delete media',
            'details' => $e->getMessage(),
        ]);
    }
}

function extension_from_storage_key(string $storageKey): string
{
    $path = parse_url($storageKey, PHP_URL_PATH);
    $path = is_string($path) ? $path : $storageKey;

    $extension = pathinfo($path, PATHINFO_EXTENSION);

    return is_string($extension) && $extension !== '' ? strtolower($extension) : 'bin';
}