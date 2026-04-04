<?php
declare(strict_types=1);

abstract class StorageDriver
{
    protected array $params;

    public function __construct(array $params = [])
    {
        $this->params = $params;
    }

    abstract public function put(
        string $sourceFile,
        string $key,
        string $contentType
    ): void;

    abstract public function delete(string $key): void;

    abstract public function createUploadInstruction(
        string $key,
        string $contentType
    ): array;

    /**
     * Confirm the uploaded object exists and apply final access controls.
     */
    abstract public function finalizeUpload(
        string $key,
        string $contentType
    ): void;

    abstract public function getPublicUrl(string $key): string;
}