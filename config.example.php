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
        'image/png' => 'png',
        'video/quicktime' => 'mov',
    ],
];