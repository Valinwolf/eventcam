<?php
declare(strict_types=1);

function album_respond_error(string $message): void
{
    throw new RuntimeException($message);
}

function album_default(string $eventCode, string $name): array
{
    return [
        'event_code' => $eventCode,
        'name' => $name,
        'created_at' => gmdate('c'),
        'uploads' => [
            'photos' => [],
            'videos' => [],
        ],
    ];
}

function album_normalize(array $album, string $eventCode, string $name): array
{
    $default = album_default($eventCode, $name);

    if (!isset($album['event_code']) || !is_string($album['event_code'])) {
        $album['event_code'] = $default['event_code'];
    }

    if (!isset($album['name']) || !is_string($album['name'])) {
        $album['name'] = $default['name'];
    }

    if (!isset($album['created_at']) || !is_string($album['created_at'])) {
        $album['created_at'] = $default['created_at'];
    }

    if (!isset($album['uploads']) || !is_array($album['uploads'])) {
        $album['uploads'] = $default['uploads'];
    }

    if (!isset($album['uploads']['photos']) || !is_array($album['uploads']['photos'])) {
        $album['uploads']['photos'] = [];
    }

    if (!isset($album['uploads']['videos']) || !is_array($album['uploads']['videos'])) {
        $album['uploads']['videos'] = [];
    }

    foreach (['photos', 'videos'] as $bucket) {
        foreach ($album['uploads'][$bucket] as $index => $item) {
            if (!is_array($item)) {
                unset($album['uploads'][$bucket][$index]);
                continue;
            }

            if (!isset($item['control_token']) || !is_string($item['control_token'])) {
                $album['uploads'][$bucket][$index]['control_token'] = '';
            }
        }

        $album['uploads'][$bucket] = array_values($album['uploads'][$bucket]);
    }

    return $album;
}

function album_read_from_handle($handle, string $eventCode, string $name): array
{
    rewind($handle);
    $raw = stream_get_contents($handle);

    if ($raw === false || trim($raw) === '') {
        return album_default($eventCode, $name);
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return album_default($eventCode, $name);
    }

    return album_normalize($decoded, $eventCode, $name);
}

function album_write_to_handle($handle, array $album): void
{
    $json = json_encode($album, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        album_respond_error('Failed to encode album JSON');
    }

    rewind($handle);

    if (!ftruncate($handle, 0)) {
        album_respond_error('Failed to truncate album JSON');
    }

    if (fwrite($handle, $json) === false) {
        album_respond_error('Failed to write album JSON');
    }

    fflush($handle);
}

function album_get_next_id(array $album, string $bucket): int
{
    $max = 0;

    if (!isset($album['uploads'][$bucket]) || !is_array($album['uploads'][$bucket])) {
        return 1;
    }

    foreach ($album['uploads'][$bucket] as $item) {
        if (is_array($item) && isset($item['id']) && is_numeric($item['id'])) {
            $id = (int)$item['id'];
            if ($id > $max) {
                $max = $id;
            }
        }
    }

    return $max + 1;
}

function album_generate_control_token(): string
{
    return bin2hex(random_bytes(32));
}

function album_reserve_upload_entry(
    string $albumPath,
    string $eventCode,
    string $name,
    string $bucket,
    string $basePrefix,
    string $extension
): array {
    $handle = fopen($albumPath, 'c+');
    if ($handle === false) {
        album_respond_error('Failed to open album JSON');
    }

    try {
        if (!flock($handle, LOCK_EX)) {
            album_respond_error('Failed to lock album JSON');
        }

        $album = album_read_from_handle($handle, $eventCode, $name);
        $id = album_get_next_id($album, $bucket);
        $fileName = $id . '.' . $extension;
        $storageKey = $basePrefix . '/' . $eventCode . '/' . $name . '/' . $fileName;
        $controlToken = album_generate_control_token();
        $timestamp = gmdate('c');

        $album['updated_at'] = $timestamp;
        $album['uploads'][$bucket][] = [
            'id' => $id,
            'file' => $fileName,
            'storage_key' => $storageKey,
            'control_token' => $controlToken,
            'uploaded_at' => $timestamp,
        ];

        album_write_to_handle($handle, $album);

        flock($handle, LOCK_UN);

        return [
            'id' => $id,
            'file' => $fileName,
            'storage_key' => $storageKey,
            'control_token' => $controlToken,
            'bucket' => $bucket,
        ];
    } finally {
        fclose($handle);
    }
}

function album_remove_upload_entry(string $albumPath, string $bucket, int $id): void
{
    $handle = fopen($albumPath, 'c+');
    if ($handle === false) {
        return;
    }

    try {
        if (!flock($handle, LOCK_EX)) {
            return;
        }

        $rawAlbum = album_read_from_handle($handle, '', '');

        if (!isset($rawAlbum['uploads'][$bucket]) || !is_array($rawAlbum['uploads'][$bucket])) {
            flock($handle, LOCK_UN);
            return;
        }

        $rawAlbum['uploads'][$bucket] = array_values(array_filter(
            $rawAlbum['uploads'][$bucket],
            static function ($item) use ($id): bool {
                return !(
                    is_array($item) &&
                    isset($item['id']) &&
                    (int)$item['id'] === $id
                );
            }
        ));

        $rawAlbum['updated_at'] = gmdate('c');
        album_write_to_handle($handle, $rawAlbum);

        flock($handle, LOCK_UN);
    } finally {
        fclose($handle);
    }
}

function album_find_upload_by_control_token(string $eventDir, string $controlToken): ?array
{
    if (!is_dir($eventDir)) {
        return null;
    }

    $albumFiles = glob($eventDir . '/*.json');
    if ($albumFiles === false) {
        return null;
    }

    foreach ($albumFiles as $albumPath) {
        $raw = file_get_contents($albumPath);
        if ($raw === false || trim($raw) === '') {
            continue;
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            continue;
        }

        $album = album_normalize($decoded, '', '');

        foreach (['photos', 'videos'] as $bucket) {
            foreach ($album['uploads'][$bucket] as $item) {
                if (
                    is_array($item) &&
                    isset($item['control_token']) &&
                    is_string($item['control_token']) &&
                    hash_equals($item['control_token'], $controlToken)
                ) {
                    return [
                        'album_path' => $albumPath,
                        'bucket' => $bucket,
                        'id' => isset($item['id']) ? (int)$item['id'] : 0,
                        'file' => (string)($item['file'] ?? ''),
                        'storage_key' => (string)($item['storage_key'] ?? ''),
                        'control_token' => (string)$item['control_token'],
                        'name' => (string)($album['name'] ?? ''),
                        'event_code' => (string)($album['event_code'] ?? ''),
                    ];
                }
            }
        }
    }

    return null;
}

function album_remove_upload_entry_by_control_token(string $albumPath, string $controlToken): bool
{
    $handle = fopen($albumPath, 'c+');
    if ($handle === false) {
        return false;
    }

    try {
        if (!flock($handle, LOCK_EX)) {
            return false;
        }

        $album = album_read_from_handle($handle, '', '');
        $removed = false;

        foreach (['photos', 'videos'] as $bucket) {
            $beforeCount = count($album['uploads'][$bucket]);

            $album['uploads'][$bucket] = array_values(array_filter(
                $album['uploads'][$bucket],
                static function ($item) use ($controlToken): bool {
                    return !(
                        is_array($item) &&
                        isset($item['control_token']) &&
                        is_string($item['control_token']) &&
                        hash_equals($item['control_token'], $controlToken)
                    );
                }
            ));

            if (count($album['uploads'][$bucket]) !== $beforeCount) {
                $removed = true;
            }
        }

        if ($removed) {
            $album['updated_at'] = gmdate('c');
            album_write_to_handle($handle, $album);
        }

        flock($handle, LOCK_UN);

        return $removed;
    } finally {
        fclose($handle);
    }
}