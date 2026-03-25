<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/storage.php';
require_once __DIR__ . '/../includes/exceptions.php';

use Aws\S3\S3Client;
use Aws\Exception\AwsException;

class Storage_S3 extends StorageDriver
{
    protected S3Client $client;
    protected string $bucket;
    protected string $acl;

    public function __construct(array $params = [])
    {
        parent::__construct($params);

        $this->bucket = (string)($params['bucket'] ?? '');
        $this->acl = (string)($params['acl'] ?? 'public-read');

        if ($this->bucket === '') {
            throw new ConfigException('Missing S3 bucket');
        }

        $config = [
            'version' => 'latest',
            'region' => (string)($params['region'] ?? 'us-east-1'),
            'credentials' => [
                'key' => (string)($params['key'] ?? ''),
                'secret' => (string)($params['secret'] ?? ''),
            ],
        ];

        if (!empty($params['endpoint'])) {
            $config['endpoint'] = $params['endpoint'];
        }

        if (!empty($params['use_path_style_endpoint'])) {
            $config['use_path_style_endpoint'] = true;
        }

        $this->client = new S3Client($config);
    }

    /*
    |--------------------------------------------------------------------------
    | Server-side upload (fallback)
    |--------------------------------------------------------------------------
    */
    public function put(string $sourceFile, string $key, string $contentType): void
    {
        try {
            $this->client->putObject([
                'Bucket' => $this->bucket,
                'Key' => $key,
                'SourceFile' => $sourceFile,
                'ContentType' => $contentType,
                'ACL' => $this->acl,
            ]);
        } catch (AwsException $e) {
            throw new DriverException('S3 put failed: ' . $e->getMessage(), 0, $e);
        }
    }

    /*
    |--------------------------------------------------------------------------
    | Delete object
    |--------------------------------------------------------------------------
    */
    public function delete(string $key): void
    {
        try {
            $this->client->deleteObject([
                'Bucket' => $this->bucket,
                'Key' => $key,
            ]);
        } catch (AwsException $e) {
            throw new DriverException('S3 delete failed: ' . $e->getMessage(), 0, $e);
        }
    }

    /*
    |--------------------------------------------------------------------------
    | Create pre-signed upload instruction
    |--------------------------------------------------------------------------
    */
    public function createUploadInstruction(string $key, string $contentType): array
    {
        try {
            $cmd = $this->client->getCommand('PutObject', [
                'Bucket' => $this->bucket,
                'Key' => $key,
                'ContentType' => $contentType,
                'ACL' => $this->acl,
            ]);

            $request = $this->client->createPresignedRequest(
                $cmd,
                '+15 minutes'
            );

            $uri = $request->getUri();

            return [
                'method' => 'PUT',
                'url' => (string)$uri,
                'headers' => [
                    'Content-Type' => $contentType,
                ],
                'expires_at' => gmdate('c', time() + (15 * 60)),
            ];
        } catch (AwsException $e) {
            throw new DriverException('Failed to create upload URL: ' . $e->getMessage(), 0, $e);
        }
    }

    /*
    |--------------------------------------------------------------------------
    | Resolve public URL
    |--------------------------------------------------------------------------
    */
    public function getPublicUrl(string $key): string
    {
        if (!empty($this->params['endpoint'])) {
            $endpoint = rtrim((string)$this->params['endpoint'], '/');
            return "{$endpoint}/{$this->bucket}/{$key}";
        }

        return "https://{$this->bucket}.s3.amazonaws.com/{$key}";
    }
}