<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/database.php';
require_once __DIR__ . '/../includes/exceptions.php';

class Database_Postgres extends DatabaseDriver
{
    protected ?PDO $connection = null;

    public function connect(): void
    {
        if ($this->connection instanceof PDO) {
            return;
        }

        $host = (string)($this->params['host'] ?? '127.0.0.1');
        $port = (int)($this->params['port'] ?? 5432);
        $dbname = (string)($this->params['dbname'] ?? '');
        $user = (string)($this->params['user'] ?? '');
        $password = (string)($this->params['password'] ?? '');
        $sslmode = (string)($this->params['sslmode'] ?? '');
        $schema = (string)($this->params['schema'] ?? 'public');

        if ($dbname === '' || $user === '') {
            throw new ConfigException('Invalid PostgreSQL config');
        }

        $dsn = "pgsql:host={$host};port={$port};dbname={$dbname}";
        if ($sslmode !== '') {
            $dsn .= ";sslmode={$sslmode}";
        }

        try {
            $this->connection = new PDO($dsn, $user, $password, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);

            $this->connection->exec('SET search_path TO ' . $schema);
        } catch (PDOException $e) {
            throw new DriverException($e->getMessage(), 0, $e);
        }
    }

    public function isConnected(): bool
    {
        return $this->connection instanceof PDO;
    }

    public function getConnection(): mixed
    {
        if (!$this->isConnected()) {
            $this->connect();
        }
        return $this->connection;
    }

    public function getEvent(string $eventCode): ?array
    {
        $stmt = $this->getConnection()->prepare(
            'SELECT * FROM events WHERE event_code = :code LIMIT 1'
        );
        $stmt->execute(['code' => $eventCode]);

        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }

        return [
            'event_code' => $row['event_code'],
            'event_name' => $row['event_name'],
            'event_start' => $row['event_start'],
            'event_end' => $row['event_end'],
            'gallery_released' => (bool)$row['gallery_released'],
            'host_names' => json_decode($row['host_names'] ?? '[]', true) ?? [],
            'allow_photos' => (bool)$row['allow_photos'],
            'allow_videos' => (bool)$row['allow_videos'],
            'max_photos' => $row['max_photos'],
            'max_guests' => $row['max_guests'],
        ];
    }

    public function putGuest(string $name): array
    {
        $uuid = $this->uuid();

        $stmt = $this->getConnection()->prepare(
            'INSERT INTO guests (id, name) VALUES (:id, :name)'
        );

        $stmt->execute([
            'id' => $uuid,
            'name' => $name,
        ]);

        return [
            'id' => $uuid,
            'name' => $name,
        ];
    }

    public function getGuestsByEvent(string $eventCode): array
    {
        $stmt = $this->getConnection()->prepare(
            'SELECT DISTINCT g.id, g.name
             FROM guests g
             JOIN media m ON m.guest_id = g.id
             WHERE m.event_code = :event'
        );

        $stmt->execute(['event' => $eventCode]);

        return $stmt->fetchAll();
    }

    public function createMedia(string $eventCode, string $guestId, string $mime, string $extension): array
    {
        $pdo = $this->getConnection();

        $event = $this->getEvent($eventCode);
        if (!$event) {
            throw new DriverException('Event not found');
        }

        if ($mime === 'image/png' && !$event['allow_photos']) {
            throw new DriverException('Photo uploads are disabled for this event');
        }

        if ($mime === 'video/quicktime' && !$event['allow_videos']) {
            throw new DriverException('Video uploads are disabled for this event');
        }

        $uuid = $this->uuid();
        $token = bin2hex(random_bytes(32));

        $type = str_starts_with($mime, 'video') ? 'video' : 'photo';
        $storageKey = "uploads/{$eventCode}/{$uuid}.{$extension}";

        $stmt = $pdo->prepare(
            'INSERT INTO media (
                id,
                event_code,
                guest_id,
                mime,
                type,
                extension,
                storage_key,
                control_token,
                control_token_expires_at,
                status
            ) VALUES (
                :id,
                :event,
                :guest,
                :mime,
                :type,
                :extension,
                :key,
                :token,
                :token_expires_at,
                :status
            )'
        );

        $stmt->execute([
            'id' => $uuid,
            'event' => $eventCode,
            'guest' => $guestId,
            'mime' => $mime,
            'type' => $type,
            'extension' => $extension,
            'key' => $storageKey,
            'token' => $token,
            'token_expires_at' => $event['event_end'] ?? null,
            'status' => 'pending',
        ]);

        $guestStmt = $pdo->prepare('SELECT id, name FROM guests WHERE id = :id LIMIT 1');
        $guestStmt->execute(['id' => $guestId]);
        $guest = $guestStmt->fetch();

        if (!$guest) {
            throw new DriverException('Guest not found');
        }

        $file = substr(str_replace('-', '', strtolower($uuid)), 0, 3)
            . '-'
            . substr(str_replace('-', '', strtolower($uuid)), -4)
            . '.'
            . $extension;

        return [
            'id' => $uuid,
            'event_code' => $eventCode,
            'guest' => [
                'id' => (string)$guest['id'],
                'name' => (string)$guest['name'],
            ],
            'type' => $type,
            'mime' => $mime,
            'extension' => $extension,
            'file' => $file,
            'storage_key' => $storageKey,
            'control_token' => $token,
            'control_token_expires_at' => $event['event_end'] ?? null,
            'status' => 'pending',
            'failed_reason' => null,
            'taken_at' => null,
            'created_at' => null,
            'uploaded_at' => null,
            'deleted_at' => null,
        ];
    }

    public function getMediaById(string $id): ?array
    {
        $stmt = $this->getConnection()->prepare(
            'SELECT * FROM media WHERE id = :id LIMIT 1'
        );
        $stmt->execute(['id' => $id]);

        return $stmt->fetch() ?: null;
    }

    public function getMediaByGuest(string $eventCode, string $guestId): ?array
    {
        $stmt = $this->getConnection()->prepare(
            'SELECT m.*, g.name
             FROM media m
             JOIN guests g ON g.id = m.guest_id
             WHERE m.event_code = :event
               AND m.guest_id = :guest
               AND m.status = \'uploaded\'
               AND m.deleted_at IS NULL'
        );

        $stmt->execute([
            'event' => $eventCode,
            'guest' => $guestId,
        ]);

        $rows = $stmt->fetchAll();

        if (!$rows) {
            return null;
        }

        return [
            'guest' => [
                'id' => $guestId,
                'name' => $rows[0]['name'],
            ],
            'media' => array_map(function ($r) {
                return [
                    'id' => $r['id'],
                    'storage_key' => $r['storage_key'],
                    'type' => $r['type'],
                    'taken' => $r['taken_at'],
                ];
            }, $rows),
        ];
    }

    public function patchMediaStatus(string $id, string $status, ?string $reason = null): ?array
    {
        $stmt = $this->getConnection()->prepare(
            'UPDATE media
             SET status = :status,
                 failed_reason = :reason,
                 uploaded_at = CASE WHEN :status = \'uploaded\' THEN NOW() ELSE uploaded_at END
             WHERE id = :id'
        );

        $stmt->execute([
            'id' => $id,
            'status' => $status,
            'reason' => $reason,
        ]);

        return $this->getMediaById($id);
    }

    public function findMediaForDelete(string $id, string $token): ?array
    {
        $stmt = $this->getConnection()->prepare(
            'SELECT * FROM media WHERE id = :id AND control_token = :token'
        );

        $stmt->execute([
            'id' => $id,
            'token' => $token,
        ]);

        return $stmt->fetch() ?: null;
    }

    public function markMediaDeleted(string $id): bool
    {
        $stmt = $this->getConnection()->prepare(
            'UPDATE media SET deleted_at = NOW(), status = \'deleted\' WHERE id = :id'
        );

        $stmt->execute(['id' => $id]);

        return $stmt->rowCount() > 0;
    }

    public function markMediaFailed(string $id, ?string $reason = null): ?array
    {
        return $this->patchMediaStatus($id, 'failed', $reason);
    }

    public function markMediaUploaded(string $id): ?array
    {
        return $this->patchMediaStatus($id, 'uploaded');
    }

    public function getGallery(string $eventCode): ?array
    {
        $stmt = $this->getConnection()->prepare(
            'SELECT m.*, g.name
             FROM media m
             JOIN guests g ON g.id = m.guest_id
             WHERE m.event_code = :event
               AND m.status = \'uploaded\'
               AND m.deleted_at IS NULL
             ORDER BY m.taken_at NULLS LAST, m.uploaded_at'
        );

        $stmt->execute(['event' => $eventCode]);

        return $stmt->fetchAll();
    }

    private function uuid(): string
    {
        $data = random_bytes(16);
        $data[6] = chr((ord($data[6]) & 0x0f) | 0x40);
        $data[8] = chr((ord($data[8]) & 0x3f) | 0x80);

        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
    }
}