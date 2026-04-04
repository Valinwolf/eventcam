<?php
declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../includes/storage.php';
require_once __DIR__ . '/../includes/exceptions.php';

use Aws\Exception\AwsException;
use Aws\S3\S3Client;

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

    public function put(string $sourceFile, string $key, string $contentType): void
    {
        try {
            $args = [
                'Bucket' => $this->bucket,
                'Key' => $key,
                'SourceFile' => $sourceFile,
                'ContentType' => $contentType,
            ];

            if ($this->acl !== '') {
                $args['ACL'] = $this->acl;
            }

            $this->client->putObject($args);
        } catch (AwsException $e) {
            throw new DriverException('S3 put failed: ' . $e->getMessage(), 0, $e);
        }
    }

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

    public function createUploadInstruction(string $key, string $contentType): array
    {
        try {
            $cmd = $this->client->getCommand('PutObject', [
                'Bucket' => $this->bucket,
                'Key' => $key,
                'ContentType' => $contentType,
            ]);

            $request = $this->client->createPresignedRequest($cmd, '+15 minutes');
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

    public function finalizeUpload(string $key, string $contentType): void
    {
        try {
            $head = $this->client->headObject([
                'Bucket' => $this->bucket,
                'Key' => $key,
            ]);

            if (!$head) {
                throw new DriverException('Uploaded object not found');
            }

            if ($this->acl !== '') {
                $this->client->putObjectAcl([
                    'Bucket' => $this->bucket,
                    'Key' => $key,
                    'ACL' => $this->acl,
                ]);
            }
        } catch (AwsException $e) {
            throw new DriverException('Failed to finalize upload: ' . $e->getMessage(), 0, $e);
        }
    }

    public function getPublicUrl(string $key): string
    {
        if (!empty($this->params['cdn_endpoint'])) {
            $cdn = rtrim((string)$this->params['cdn_endpoint'], '/');
            return "{$cdn}/{$key}";
        }

        if (!empty($this->params['endpoint'])) {
            $endpoint = rtrim((string)$this->params['endpoint'], '/');

            if (!empty($this->params['use_path_style_endpoint'])) {
                return "{$endpoint}/{$this->bucket}/{$key}";
            }

            $host = preg_replace('#^https?://#', '', $endpoint);
            return "https://{$this->bucket}.{$host}/{$key}";
        }

        return "https://{$this->bucket}.s3.amazonaws.com/{$key}";
    }
}