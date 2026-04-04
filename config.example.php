<?php
declare(strict_types=1);

return [
    'max_file_size' => 3 * 1024 * 1024 * 1024,

    'storage_driver' => 'S3',

    'storage_params' => [
        'bucket' => 'your-bucket-name',
        'region' => 'us-east-1',
        'endpoint' => '',
        'use_path_style_endpoint' => false,
        'key' => '',
        'secret' => '',
        'base_prefix' => 'uploads',
        'acl' => 'public-read',
    ],

    'database_driver' => 'Postgres',

    'database_params' => [
        'host' => '127.0.0.1',
        'port' => 5432,
        'dbname' => 'eventcam',
        'user' => 'eventcam',
        'password' => '',
        'sslmode' => '',
        'schema' => 'public',
    ],

    'allowed_mime_types' => [
        // photos
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        'image/heic' => 'heic',
        'image/heif' => 'heif',
        'image/avif' => 'avif',

        // videos
        'video/mp4' => 'mp4',
        'video/quicktime' => 'mov',
        'video/webm' => 'webm',
        'video/3gpp' => '3gp',
        'video/3gpp2' => '3g2',
        'video/x-matroska' => 'mkv',
        'video/ogg' => 'ogv',
    ],
];