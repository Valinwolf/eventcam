<?php
declare(strict_types=1);

abstract class StorageDriver
{
    protected array $params;

    public function __construct(array $params = [])
    {
        $this->params = $params;
    }

    /**
     * Store a local file at the given storage key.
     */
    abstract public function put(
        string $sourceFile,
        string $key,
        string $contentType
    ): void;

    /**
     * Delete an object by storage key.
     */
    abstract public function delete(string $key): void;

    /**
     * Create an upload instruction payload for direct app upload.
     *
     * Expected return shape:
     * [
     *   'method' => string, // e.g. PUT
     *   'url' => string,
     *   'headers' => array<string, string>,
     *   'expires_at' => string|null,
     * ]
     */
    abstract public function createUploadInstruction(
        string $key,
        string $contentType
    ): array;

    /**
     * Resolve a public URL for the given storage key.
     */
    abstract public function getPublicUrl(string $key): string;
}