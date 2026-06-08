-- =============================================================================
-- ADEC Sensor Network Tracker: AUTHORITATIVE CURRENT SCHEMA
-- =============================================================================
-- This file is the single source of truth for the live database structure,
-- reverse-engineered directly from the production Supabase/PostgreSQL database
-- (information_schema + pg_constraint + pg_indexes). It supersedes the older,
-- stale `supabase-schema.sql` at the repo root.
--
-- Generated: 2026-06-08, for the State of Alaska handoff (Supabase -> MS SQL).
--
-- HOW TO READ THIS FOR A MICROSOFT SQL SERVER MIGRATION
-- -----------------------------------------------------
-- PostgreSQL features used here that DO NOT exist (or differ) in MS SQL Server.
-- Each is tagged inline below with [MSSQL: ...]. Summary:
--
--   1. text[] ARRAY columns (sensors.status, contacts.communities,
--      service_tickets.sensor_ids, collocations.sensor_ids, notes.merged_sf_ids,
--      comms.merged_sf_ids). MS SQL has no array type. Options: a child table
--      (one row per value, the cleanest relational choice) or a delimited
--      string / JSON column. A child table is recommended for the tag-like ones.
--
--   2. jsonb columns (audits/collocations analysis_results, analysis_chart_data).
--      MS SQL uses NVARCHAR(MAX) validated with ISJSON()/JSON_VALUE(), or store
--      as-is. No native jsonb type.
--
--   3. gen_random_uuid() default -> MS SQL: NEWID() (or NEWSEQUENTIALID()).
--      uuid type -> MS SQL: UNIQUEIDENTIFIER.
--
--   4. timestamptz (timestamp with time zone) -> MS SQL: DATETIMEOFFSET.
--      now() default -> MS SQL: SYSDATETIMEOFFSET().
--
--   5. text type -> MS SQL: NVARCHAR(MAX) (or sized NVARCHAR where appropriate).
--
--   6. Row Level Security (RLS) policies are NOT reproduced here: they are a
--      Supabase/Postgres access-control layer enforced by the `authenticated`
--      JWT role. MS SQL has its own security model (schema/role grants, or
--      row-level security predicates). See supabase/migrations/ + SECURITY.md
--      for the current policy set. The application also relies on Supabase Auth
--      (auth.users); MS SQL will need its own identity/user store. The
--      `profiles.id -> auth.users(id)` FK below is the one Supabase-internal
--      dependency to re-home.
--
--   7. Partial indexes (WHERE ...) and GIN indexes exist below. MS SQL supports
--      filtered indexes (CREATE INDEX ... WHERE ...) but has no GIN; the GIN on
--      service_tickets.sensor_ids becomes moot if arrays become a child table.
--
-- LOGICAL-BUT-UNENFORCED REFERENCES (denormalized by design)
-- ----------------------------------------------------------
-- These text columns point at other rows but have NO foreign key, on purpose:
--   * note_tags.tag_id / comm_tags.tag_id are polymorphic: they resolve to a sensor,
--       community, OR contact depending on tag_type (mixed PK types make a real
--       FK impossible). The app filters dangling tags defensively.
--   * sensors / install_history / service_tickets sensor references by text id.
--   * audits.community_id, audits.audit_pod_id, audits.community_pod_id: loose
--       text (audits can reference imported pods not in the sensors table).
-- For MS SQL these can either stay loose or gain enforced FKs once the data is
-- known clean (see the orphan-tag cleanup performed during handoff prep).
-- =============================================================================


-- ---------------------------------------------------------------------------
-- profiles: app users (1:1 with Supabase Auth users)
-- [MSSQL] The auth.users FK is Supabase-specific; re-point to your identity store.
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
    id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email      text,
    name       text,
    role       text DEFAULT 'user',           -- 'user' | 'admin'
    created_at timestamptz DEFAULT now()
);


-- ---------------------------------------------------------------------------
-- communities: the ~40 AK communities (+ regulatory sites & labs). Self-
-- referencing for sub-communities (e.g. school sites under a district).
-- ---------------------------------------------------------------------------
CREATE TABLE public.communities (
    id                   text PRIMARY KEY,     -- human-readable slug, e.g. 'bethel'
    name                 text NOT NULL,
    parent_id            text REFERENCES public.communities(id),
    active               boolean DEFAULT true,
    details              text DEFAULT '',
    network_availability text DEFAULT '',
    created_at           timestamptz DEFAULT now(),
    updated_at           timestamptz DEFAULT now(),
    updated_by           uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);


-- ---------------------------------------------------------------------------
-- sensors: physical QuantAQ Modulair pods (and a few other LCS units).
-- ---------------------------------------------------------------------------
CREATE TABLE public.sensors (
    id                text PRIMARY KEY,         -- e.g. 'MOD-00451', 'MOD-X-PM-01760'
    soa_tag_id        text DEFAULT '',
    type              text DEFAULT 'Community Pod',
    status            text[] DEFAULT '{}',      -- [MSSQL] array -> child table or JSON
    community_id      text REFERENCES public.communities(id),
    location          text DEFAULT '',
    date_purchased    text DEFAULT '',          -- stored as text; see date note
    date_installed    text DEFAULT '',
    collocation_dates text DEFAULT '',
    details           text DEFAULT '',
    active            boolean DEFAULT true,      -- soft-delete: active vs archived
    archived_at       timestamptz,
    archived_by       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at        timestamptz DEFAULT now(),
    updated_at        timestamptz DEFAULT now(),
    updated_by        uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE INDEX idx_sensors_active ON public.sensors(active);


-- ---------------------------------------------------------------------------
-- contacts: people at each community (and non-community contacts).
-- ---------------------------------------------------------------------------
CREATE TABLE public.contacts (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    role            text DEFAULT '',
    org             text DEFAULT '',
    email           text DEFAULT '',
    phone           text DEFAULT '',
    community_id    text REFERENCES public.communities(id),   -- first/legacy community
    communities     text[] NOT NULL DEFAULT '{}',  -- a contact may serve several; [MSSQL] array
    email_list      boolean DEFAULT false,
    primary_contact boolean DEFAULT false,
    active          boolean DEFAULT true,
    created_at      timestamptz DEFAULT now(),
    updated_at      timestamptz DEFAULT now(),
    updated_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE INDEX idx_contacts_community_id ON public.contacts(community_id);
CREATE INDEX idx_contacts_communities  ON public.contacts USING gin (communities);  -- [MSSQL] GIN n/a


-- ---------------------------------------------------------------------------
-- notes: log entries (issues, installs, moves, general). Cross-tagged to
-- sensors/communities/contacts via note_tags. Soft-deletable (trash bin).
-- source/sf_id/merged_sf_ids/logged_by track Salesforce-imported records.
-- ---------------------------------------------------------------------------
CREATE TABLE public.notes (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    date            timestamptz DEFAULT now(),
    type            text DEFAULT 'General',
    text            text DEFAULT '',
    additional_info text DEFAULT '',
    source          text DEFAULT 'manual',     -- 'manual' | 'salesforce_import'
    sf_id           text,                       -- Salesforce record id (if imported)
    merged_sf_ids   text[] DEFAULT '{}',        -- absorbed duplicate sf ids; [MSSQL] array
    logged_by       text DEFAULT '',            -- original SF author (not an app user)
    created_by      uuid REFERENCES public.profiles(id),
    created_at      timestamptz DEFAULT now(),
    updated_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_at      timestamptz,
    deleted_at      timestamptz,
    deleted_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX uq_notes_sf_id ON public.notes(sf_id) WHERE sf_id IS NOT NULL;
CREATE INDEX idx_notes_deleted_at ON public.notes(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_notes_date ON public.notes(date DESC);


-- ---------------------------------------------------------------------------
-- comms: communications (calls/emails/site visits). Cross-tagged via comm_tags.
-- ---------------------------------------------------------------------------
CREATE TABLE public.comms (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    date          timestamptz DEFAULT now(),
    comm_type     text DEFAULT 'Email',
    subject       text DEFAULT '',
    text          text DEFAULT '',
    full_body     text DEFAULT '',
    community_id  text REFERENCES public.communities(id),
    source        text DEFAULT 'manual',
    sf_id         text,
    merged_sf_ids text[] DEFAULT '{}',          -- [MSSQL] array
    logged_by     text DEFAULT '',
    created_by    uuid REFERENCES public.profiles(id),
    created_at    timestamptz DEFAULT now(),
    updated_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_at    timestamptz,
    deleted_at    timestamptz,
    deleted_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX uq_comms_sf_id ON public.comms(sf_id) WHERE sf_id IS NOT NULL;
CREATE INDEX idx_comms_deleted_at ON public.comms(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_comms_community_id ON public.comms(community_id);
CREATE INDEX idx_comms_date ON public.comms(date DESC);


-- ---------------------------------------------------------------------------
-- note_tags / comm_tags: POLYMORPHIC cross-reference. One row links a note (or
-- comm) to a sensor, community, or contact. tag_id is text and has NO FK (it
-- resolves to a different table per tag_type). [MSSQL] keep as-is, or split into
-- three typed link tables for enforced integrity.
-- ---------------------------------------------------------------------------
CREATE TABLE public.note_tags (
    id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id  uuid NOT NULL REFERENCES public.notes(id) ON DELETE CASCADE,
    tag_type text NOT NULL CHECK (tag_type IN ('sensor', 'community', 'contact')),
    tag_id   text NOT NULL
);
CREATE INDEX idx_note_tags_note_id ON public.note_tags(note_id);
CREATE INDEX idx_note_tags_lookup  ON public.note_tags(tag_type, tag_id);

CREATE TABLE public.comm_tags (
    id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comm_id  uuid NOT NULL REFERENCES public.comms(id) ON DELETE CASCADE,
    tag_type text NOT NULL CHECK (tag_type IN ('contact', 'community')),
    tag_id   text NOT NULL
);
CREATE INDEX idx_comm_tags_comm_id ON public.comm_tags(comm_id);
CREATE INDEX idx_comm_tags_lookup  ON public.comm_tags(tag_type, tag_id);


-- ---------------------------------------------------------------------------
-- community_tags: free-text LABELS on a community (e.g. 'Regulatory Site').
-- NOTE: unrelated to comm_tags above despite the similar name. Documented as a
-- known naming trap for the new team.
-- ---------------------------------------------------------------------------
CREATE TABLE public.community_tags (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    community_id text NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
    tag          text NOT NULL,
    UNIQUE (community_id, tag)
);


-- ---------------------------------------------------------------------------
-- community_files: uploaded files (stored in Supabase Storage; storage_path is
-- the bucket path). [MSSQL] file blobs will need a new storage strategy.
-- ---------------------------------------------------------------------------
CREATE TABLE public.community_files (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    community_id text NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
    file_name    text NOT NULL,
    file_type    text DEFAULT '',
    storage_path text NOT NULL,
    source       text DEFAULT 'manual',
    sf_id        text,
    uploaded_by  uuid REFERENCES public.profiles(id),
    created_at   timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX uq_files_sf_id ON public.community_files(sf_id) WHERE sf_id IS NOT NULL;
CREATE INDEX idx_community_files_comm ON public.community_files(community_id);


-- ---------------------------------------------------------------------------
-- audits: audit-pod collocations against a community pod. notes is a JSON
-- string array of progress notes. community_id / *_pod_id are loose text.
-- ---------------------------------------------------------------------------
CREATE TABLE public.audits (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    audit_pod_id         text,                  -- loose pod ref (no FK)
    community_pod_id     text,                  -- loose pod ref (no FK)
    community_id         text NOT NULL,         -- loose community ref (no FK)
    status               text NOT NULL DEFAULT 'Scheduled',
    start_date           text,                  -- text date; see date note
    end_date             text,
    conducted_by         text DEFAULT '',
    notes                text DEFAULT '',       -- JSON array stored as text
    analysis_results     jsonb DEFAULT '{}',    -- [MSSQL] jsonb -> NVARCHAR(MAX)+ISJSON
    analysis_chart_data  jsonb,                 -- [MSSQL] jsonb
    analysis_name        text DEFAULT '',
    analysis_file_path   text DEFAULT '',
    analysis_file_name   text DEFAULT '',
    analysis_upload_date timestamptz,
    analysis_uploaded_by text DEFAULT '',
    source               text DEFAULT 'manual',
    created_by           uuid REFERENCES public.profiles(id),
    created_at           timestamptz DEFAULT now(),
    updated_by           uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_at           timestamptz DEFAULT now(),
    deleted_at           timestamptz,
    deleted_by           uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE INDEX idx_audits_status       ON public.audits(status);
CREATE INDEX idx_audits_start_date   ON public.audits(start_date);
CREATE INDEX idx_audits_community_id ON public.audits(community_id);
CREATE INDEX idx_audits_deleted_at   ON public.audits(deleted_at) WHERE deleted_at IS NOT NULL;


-- ---------------------------------------------------------------------------
-- collocations: multi-pod collocation studies at a community/lab.
-- NOTE: location_id (not community_id) is the FK to communities here: the one
-- naming inconsistency in the schema, documented for the new team.
-- ---------------------------------------------------------------------------
CREATE TABLE public.collocations (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id          text REFERENCES public.communities(id),  -- != community_id naming
    status               text DEFAULT 'In Progress',
    start_date           text,
    end_date             text,
    sensor_ids           text[] DEFAULT '{}',   -- [MSSQL] array -> child table
    permanent_pod_id     text,
    bam_source           text,
    conducted_by         text DEFAULT '',
    notes                text DEFAULT '',       -- JSON array as text
    analysis_results     jsonb DEFAULT '{}',    -- [MSSQL] jsonb
    analysis_chart_data  jsonb,                 -- [MSSQL] jsonb
    analysis_name        text DEFAULT '',
    analysis_upload_date timestamptz,
    analysis_uploaded_by text DEFAULT '',
    created_by           uuid REFERENCES public.profiles(id),
    created_at           timestamptz DEFAULT now(),
    updated_by           uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_at           timestamptz DEFAULT now(),
    deleted_at           timestamptz,
    deleted_by           uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE INDEX idx_collocations_deleted_at  ON public.collocations(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_collocations_location_id ON public.collocations(location_id);


-- ---------------------------------------------------------------------------
-- service_tickets: Quant service/RMA tickets. sensor_ids[] is the canonical
-- multi-sensor list; sensor_id is the legacy single-sensor column kept for
-- back-compat. quant_notes holds a JSON array of progress notes (the column
-- name is a QuantAQ-era leftover; it is generic progress-note data).
-- ---------------------------------------------------------------------------
CREATE TABLE public.service_tickets (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sensor_id           text NOT NULL,         -- legacy single ref (loose)
    sensor_ids          text[] DEFAULT '{}',   -- canonical multi list; [MSSQL] array
    ticket_type         text NOT NULL,
    status              text NOT NULL DEFAULT 'Ticket Opened',
    rma_number          text DEFAULT '',
    fedex_tracking_to   text DEFAULT '',
    fedex_tracking_from text DEFAULT '',
    issue_description   text DEFAULT '',
    quant_notes         text DEFAULT '',       -- JSON array as text (generic progress notes)
    work_completed      text DEFAULT '',
    created_by          uuid REFERENCES public.profiles(id),
    created_at          timestamptz DEFAULT now(),
    closed_at           timestamptz,
    updated_by          uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_at          timestamptz DEFAULT now(),
    deleted_at          timestamptz,
    deleted_by          uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE INDEX idx_service_tickets_deleted_at ON public.service_tickets(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_service_tickets_sensor_ids ON public.service_tickets USING gin (sensor_ids);  -- [MSSQL] GIN n/a


-- ---------------------------------------------------------------------------
-- install_history: derived log of which pod was installed at which community
-- and when (one row per "stay"). Powers the community Install History timeline.
-- Dates are text. sensor_id is loose (no FK).
-- ---------------------------------------------------------------------------
CREATE TABLE public.install_history (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    community_id   text REFERENCES public.communities(id) ON DELETE CASCADE,
    sensor_id      text,                        -- loose pod ref (no FK)
    installed_date text,
    removed_date   text,
    created_at     timestamptz DEFAULT now()
);
CREATE INDEX idx_install_history_comm ON public.install_history(community_id);


-- ---------------------------------------------------------------------------
-- app_settings: key/value app configuration (typed-as-text grab bag).
-- Known keys: 'mfa_required', 'user_guide_body', and the guide editor flags.
-- ---------------------------------------------------------------------------
CREATE TABLE public.app_settings (
    key        text PRIMARY KEY,
    value      text NOT NULL,                   -- holds booleans ('true'), JSON, html, etc.
    updated_at timestamptz DEFAULT now(),
    updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);


-- ---------------------------------------------------------------------------
-- allowed_emails: signup allow-list (gates account creation; enforced by a
-- DB trigger + the is_email_allowed() RPC, not just the browser).
-- ---------------------------------------------------------------------------
CREATE TABLE public.allowed_emails (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email               text NOT NULL UNIQUE,
    role                text DEFAULT 'user',
    status              text DEFAULT 'active',
    can_edit_user_guide boolean NOT NULL DEFAULT false,
    added_at            timestamptz DEFAULT now()
);

-- =============================================================================
-- NOT INCLUDED HERE (intentionally):
--   * RLS policies, DB functions/RPCs, triggers, cron jobs: see
--     supabase/migrations/ and SECURITY.md. These are Supabase/Postgres-specific
--     and must be re-implemented in the MS SQL security/identity model.
--   * Supabase-managed schemas (auth, storage). profiles.id references
--     auth.users(id): the one Supabase dependency to re-home.
--   * quantaq_alerts_backup_test: a dead QuantAQ-era backup table; dropped
--     during handoff prep (not part of the app).
-- =============================================================================
