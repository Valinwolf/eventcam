<?php
declare(strict_types=1);

abstract class DatabaseDriver
{
    protected array $params;

    public function __construct(array $params = [])
    {
        $this->params = $params;
    }

    abstract public function connect(): void;

    abstract public function isConnected(): bool;

    abstract public function getConnection(): mixed;

    /**
     * Get event metadata by event code.
     *
     * Expected return shape:
     * [
     *   'event_code' => string,
     *   'event_name' => string,
     *   'event_start' => string|null,
     *   'event_end' => string|null,
     *   'gallery_released' => bool,
     *   'host_names' => string[],
     *   'allow_photos' => bool,
     *   'allow_videos' => bool,
     *   'max_photos' => int|null,
     *   'max_guests' => int|null,
     *   'business_name' => string|null,
     *   'package_name' => string|null,
     *   'notes' => string|null,
     *   'created_at' => string|null,
     *   'updated_at' => string|null,
     * ]
     */
    abstract public function getEvent(string $eventCode): ?array;

    /**
     * Create or retrieve a guest.
     *
     * Expected return shape:
     * [
     *   'id' => string, // UUID
     *   'name' => string,
     *   'created_at' => string|null,
     * ]
     */
    abstract public function putGuest(string $name): array;

    /**
     * List guests for an event.
     *
     * Expected return shape:
     * [
     *   [
     *     'id' => string, // UUID
     *     'name' => string,
     *   ],
     *   ...
     * ]
     */
    abstract public function getGuestsByEvent(string $eventCode): array;

    /**
     * Create pending media metadata and return normalized media payload.
     *
     * Expected return shape:
     * [
     *   'id' => string, // file UUID
     *   'event_code' => string,
     *   'guest' => [
     *     'id' => string,
     *     'name' => string,
     *   ],
     *   'type' => string, // photo|video
     *   'mime' => string,
     *   'extension' => string,
     *   'file' => string, // display filename like abc-1234.png
     *   'storage_key' => string,
     *   'control_token' => string,
     *   'control_token_expires_at' => string|null,
     *   'status' => string, // pending|uploaded|failed|deleted
     *   'failed_reason' => string|null,
     *   'taken_at' => string|null,
     *   'created_at' => string|null,
     *   'uploaded_at' => string|null,
     *   'deleted_at' => string|null,
     * ]
     */
    abstract public function createMedia(
        string $eventCode,
        string $guestId,
        string $mime,
        string $extension
    ): array;

    /**
     * Fetch a single media item by UUID.
     *
     * Expected return shape matches createMedia().
     */
    abstract public function getMediaById(string $id): ?array;

    /**
     * List media for a guest within an event.
     *
     * Expected return shape:
     * [
     *   'guest' => [
     *     'id' => string,
     *     'name' => string,
     *   ],
     *   'media' => [
     *     [
     *       'id' => string,
     *       'file' => string,
     *       'url' => string, // may be filled by API after storage URL resolution
     *       'storage_key' => string,
     *       'type' => string,
     *       'taken' => string|null,
     *       'uploaded_at' => string|null,
     *     ],
     *     ...
     *   ],
     * ]
     */
    abstract public function getMediaByGuest(string $eventCode, string $guestId): ?array;

    /**
     * Update media status.
     *
     * Allowed statuses are expected to be enforced by the implementation.
     * Returns normalized media payload on success, or null if not found.
     */
    abstract public function patchMediaStatus(
        string $id,
        string $status,
        ?string $reason = null
    ): ?array;

    /**
     * Find media by UUID + control token for delete flow.
     *
     * Expected return shape matches createMedia().
     */
    abstract public function findMediaForDelete(string $id, string $controlToken): ?array;

    /**
     * Mark media deleted by UUID.
     * Returns true if a row was updated.
     */
    abstract public function markMediaDeleted(string $id): bool;

    /**
     * Mark media failed by UUID.
     * Returns normalized media payload on success, or null if not found.
     */
    abstract public function markMediaFailed(string $id, ?string $reason = null): ?array;

    /**
     * Mark media uploaded by UUID.
     * Returns normalized media payload on success, or null if not found.
     */
    abstract public function markMediaUploaded(string $id): ?array;

    /**
     * Return gallery payload for an event.
     *
     * Expected return shape:
     * [
     *   'event' => string,
     *   'start' => string|null,
     *   'end' => string|null,
     *   'hosts' => string[],
     *   'gallery' => [
     *     [
     *       'id' => string,
     *       'file' => string,
     *       'storage_key' => string,
     *       'guest' => [
     *         'id' => string,
     *         'name' => string,
     *       ],
     *       'taken' => string|null,
     *       'type' => string,
     *       'uploaded_at' => string|null,
     *     ],
     *     ...
     *   ],
     * ]
     */
    abstract public function getGallery(string $eventCode): ?array;
}