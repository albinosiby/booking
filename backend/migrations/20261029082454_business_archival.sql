ALTER TABLE businesses DROP CONSTRAINT businesses_status_check;
ALTER TABLE businesses ADD CONSTRAINT businesses_status_check
 CHECK(status IN ('draft','ready','paused','archived'));
ALTER TABLE businesses ADD COLUMN archived_at timestamptz,
 ADD COLUMN archived_by text;
ALTER TABLE businesses ADD CONSTRAINT businesses_archive_metadata_check CHECK(
 (status='archived' AND archived_at IS NOT NULL AND archived_by IS NOT NULL AND length(archived_by)>0) OR
 (status<>'archived' AND archived_at IS NULL AND archived_by IS NULL));
ALTER TABLE businesses DROP CONSTRAINT businesses_organization_id_name_key;
CREATE UNIQUE INDEX businesses_current_name_idx ON businesses(organization_id,name)
 WHERE status<>'archived';
