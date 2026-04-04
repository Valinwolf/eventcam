-- EventCam PostgreSQL schema

CREATE TABLE IF NOT EXISTS guests (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS guests_name_idx
    ON guests (name);

CREATE TABLE IF NOT EXISTS events (
    event_code TEXT PRIMARY KEY,
    event_name TEXT NOT NULL,
    event_start TIMESTAMPTZ NULL,
    event_end TIMESTAMPTZ NULL,
    gallery_released BOOLEAN NOT NULL DEFAULT FALSE,
    host_names JSONB NOT NULL DEFAULT '[]'::jsonb,
    allow_photos BOOLEAN NOT NULL DEFAULT TRUE,
    allow_videos BOOLEAN NOT NULL DEFAULT TRUE,
    max_photos INTEGER NULL,
    max_guests INTEGER NULL,
    business_name TEXT NULL,
    package_name TEXT NULL,
    notes TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT events_time_range_chk
        CHECK (event_start IS NULL OR event_end IS NULL OR event_start <= event_end),
    CONSTRAINT events_host_names_array_chk
        CHECK (jsonb_typeof(host_names) = 'array'),
    CONSTRAINT events_max_photos_chk
        CHECK (max_photos IS NULL OR max_photos >= 0),
    CONSTRAINT events_max_guests_chk
        CHECK (max_guests IS NULL OR max_guests >= 0)
);

CREATE TABLE IF NOT EXISTS media (
    id UUID PRIMARY KEY,
    event_code TEXT NOT NULL REFERENCES events(event_code) ON DELETE CASCADE,
    guest_id UUID NOT NULL REFERENCES guests(id) ON DELETE RESTRICT,
    mime TEXT NOT NULL,
    type TEXT NOT NULL,
    extension TEXT NOT NULL,
    storage_key TEXT NOT NULL UNIQUE,
    control_token TEXT NOT NULL UNIQUE,
    control_token_expires_at TIMESTAMPTZ NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    failed_reason TEXT NULL,
    taken_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    uploaded_at TIMESTAMPTZ NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT media_type_chk
        CHECK (type IN ('photo', 'video')),
    CONSTRAINT media_status_chk
        CHECK (status IN ('pending', 'uploaded', 'failed', 'deleted')),
    CONSTRAINT media_deleted_status_chk
        CHECK (
            (deleted_at IS NULL AND status <> 'deleted')
            OR
            (deleted_at IS NOT NULL AND status = 'deleted')
        )
);

CREATE INDEX IF NOT EXISTS media_event_code_idx
    ON media (event_code);

CREATE INDEX IF NOT EXISTS media_guest_id_idx
    ON media (guest_id);

CREATE INDEX IF NOT EXISTS media_event_guest_idx
    ON media (event_code, guest_id);

CREATE INDEX IF NOT EXISTS media_event_status_idx
    ON media (event_code, status);

CREATE INDEX IF NOT EXISTS media_taken_at_idx
    ON media (taken_at);

CREATE INDEX IF NOT EXISTS media_uploaded_at_idx
    ON media (uploaded_at);

CREATE INDEX IF NOT EXISTS media_control_token_idx
    ON media (control_token);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_events_updated_at ON events;

CREATE TRIGGER trg_events_updated_at
BEFORE UPDATE ON events
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW gallery_media AS
SELECT
    m.id,
    m.event_code,
    e.event_name,
    e.event_start,
    e.event_end,
    e.gallery_released,
    e.host_names,
    g.id AS guest_id,
    g.name AS guest_name,
    m.type,
    m.mime,
    m.extension,
    m.storage_key,
    m.taken_at,
    m.uploaded_at,
    m.created_at
FROM media m
JOIN events e ON e.event_code = m.event_code
JOIN guests g ON g.id = m.guest_id
WHERE m.status = 'uploaded'
  AND m.deleted_at IS NULL;