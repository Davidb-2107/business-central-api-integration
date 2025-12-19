-- ============================================
-- Table: sync_checkpoints
-- Purpose: Track last processed timestamp for RAG polling
-- Date: 2025-12-19
-- ============================================

CREATE TABLE IF NOT EXISTS sync_checkpoints (
    id SERIAL PRIMARY KEY,
    sync_type VARCHAR(50) UNIQUE NOT NULL,
    company_id UUID REFERENCES bc_companies(id),
    last_processed_at TIMESTAMPTZ NOT NULL DEFAULT '1900-01-01T00:00:00Z',
    last_document_no VARCHAR(20),
    records_processed INTEGER DEFAULT 0,
    total_records_processed BIGINT DEFAULT 0,
    last_error TEXT,
    last_success_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookup by sync_type
CREATE INDEX IF NOT EXISTS idx_sync_checkpoints_type ON sync_checkpoints(sync_type);

-- Insert initial checkpoint for RAG polling
INSERT INTO sync_checkpoints (sync_type, last_processed_at)
VALUES ('rag_posted_invoices', '1900-01-01T00:00:00Z')
ON CONFLICT (sync_type) DO NOTHING;

-- ============================================
-- Function: Update timestamp on modification
-- ============================================
CREATE OR REPLACE FUNCTION update_sync_checkpoint_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for auto-update
DROP TRIGGER IF EXISTS trg_sync_checkpoints_updated ON sync_checkpoints;
CREATE TRIGGER trg_sync_checkpoints_updated
    BEFORE UPDATE ON sync_checkpoints
    FOR EACH ROW
    EXECUTE FUNCTION update_sync_checkpoint_timestamp();

-- ============================================
-- Comments
-- ============================================
COMMENT ON TABLE sync_checkpoints IS 'Tracks polling checkpoints for RAG data synchronization from Business Central';
COMMENT ON COLUMN sync_checkpoints.sync_type IS 'Type of sync: rag_posted_invoices, rag_vendors, etc.';
COMMENT ON COLUMN sync_checkpoints.last_processed_at IS 'SystemModifiedAt of last processed BC record';
