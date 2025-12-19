-- ============================================
-- Migration: Add columns to vendor_gl_mappings
-- Purpose: Support RAG polling from Posted Invoices
-- Date: 2025-12-19
-- ============================================

-- Add vendor_no for BC API lookup
ALTER TABLE vendor_gl_mappings
ADD COLUMN IF NOT EXISTS vendor_no VARCHAR(20);

-- Add full description for audit/debug
ALTER TABLE vendor_gl_mappings
ADD COLUMN IF NOT EXISTS description_full TEXT;

-- Add MANDAT dimension (critical for BC posting)
ALTER TABLE vendor_gl_mappings
ADD COLUMN IF NOT EXISTS mandat_code VARCHAR(20);

-- Add SOUS-MANDAT dimension
ALTER TABLE vendor_gl_mappings
ADD COLUMN IF NOT EXISTS sous_mandat_code VARCHAR(20);

-- Add source document for traceability
ALTER TABLE vendor_gl_mappings
ADD COLUMN IF NOT EXISTS source_document_no VARCHAR(20);

-- ============================================
-- Update index for vendor_no lookup
-- ============================================
CREATE INDEX IF NOT EXISTS idx_vendor_gl_vendor_no
ON vendor_gl_mappings(company_id, vendor_no);

-- ============================================
-- Verify structure
-- ============================================
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'vendor_gl_mappings'
ORDER BY ordinal_position;
