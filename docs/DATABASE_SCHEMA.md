# Database Schema Documentation

**Database:** Neon PostgreSQL (Frankfurt - GDPR Compliant)  
**Project ID:** `dawn-frog-92063130`  
**Last Updated:** 2025-12-19

---

## Table of Contents

1. [Overview](#overview)
2. [Entity Relationship Diagram](#entity-relationship-diagram)
3. [Tables](#tables)
   - [bc_companies](#bc_companies)
   - [invoice_vendor_mappings](#invoice_vendor_mappings)
   - [vendor_gl_mappings](#vendor_gl_mappings)
   - [pending_invoice_context](#pending_invoice_context)
   - [sync_checkpoints](#sync_checkpoints)
4. [Indexes](#indexes)
5. [Triggers & Functions](#triggers--functions)
6. [Migration History](#migration-history)

---

## Overview

This database supports the Swiss QR Invoice Automation system, providing:

- **Multi-tenant support** via `bc_companies` and `company_id` foreign keys
- **RAG-based learning** for automatic G/L account and mandate attribution
- **Polling synchronization** with Business Central posted invoices
- **Confidence scoring** for automated vs manual routing decisions

### Key Design Principles

| Principle | Implementation |
|-----------|----------------|
| GDPR Compliance | Frankfurt-hosted Neon PostgreSQL |
| Multi-tenant | All lookup tables include `company_id` |
| Auto-learning | Confidence scores increment with usage |
| Parameterized queries | Protection against SQL injection |

---

## Entity Relationship Diagram

```
┌─────────────────────┐
│    bc_companies     │
│─────────────────────│
│ id (PK, UUID)       │
│ bc_company_id       │
│ name                │
│ tenant_id           │
│ environment         │
└─────────┬───────────┘
          │
          │ 1:N
          ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌──────────────────────┐    ┌──────────────────────────┐  │
│  │ invoice_vendor_      │    │ vendor_gl_mappings       │  │
│  │ mappings             │    │                          │  │
│  │──────────────────────│    │──────────────────────────│  │
│  │ id (PK)              │    │ id (PK)                  │  │
│  │ company_id (FK)      │    │ company_id (FK)          │  │
│  │ vendor_name          │    │ vendor_name              │  │
│  │ debtor_name          │    │ vendor_no ★ NEW          │  │
│  │ client_numero        │    │ description_keyword      │  │
│  │ iban                 │    │ description_full ★ NEW   │  │
│  │ mandat_bc            │    │ gl_account_no            │  │
│  │ sous_mandat_bc       │    │ mandat_code ★ NEW        │  │
│  │ confidence           │    │ sous_mandat_code ★ NEW   │  │
│  │ usage_count          │    │ source_document_no ★ NEW │  │
│  └──────────────────────┘    │ confidence               │  │
│                              │ usage_count              │  │
│                              └──────────────────────────┘  │
│                                                             │
│  ┌──────────────────────┐    ┌──────────────────────────┐  │
│  │ pending_invoice_     │    │ sync_checkpoints ★ NEW   │  │
│  │ context              │    │                          │  │
│  │──────────────────────│    │──────────────────────────│  │
│  │ payment_reference(PK)│    │ id (PK)                  │  │
│  │ debtor_name          │    │ sync_type (UNIQUE)       │  │
│  │ vendor_name          │    │ company_id (FK)          │  │
│  │ created_at           │    │ last_processed_at        │  │
│  └──────────────────────┘    │ last_document_no         │  │
│                              │ records_processed        │  │
│                              │ total_records_processed  │  │
│                              │ last_error               │  │
│                              │ last_success_at          │  │
│                              └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Tables

### bc_companies

**Purpose:** Registry of Business Central companies for multi-tenant support.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `bc_company_id` | VARCHAR | NO | - | BC Company GUID (unique) |
| `name` | VARCHAR | NO | - | Company display name |
| `tenant_id` | VARCHAR | NO | - | Azure tenant ID |
| `environment` | VARCHAR | YES | `'Production'` | BC environment name |
| `created_at` | TIMESTAMP | YES | `now()` | Record creation timestamp |

**Indexes:**
- `bc_companies_pkey` - Primary key on `id`
- `bc_companies_bc_company_id_key` - Unique on `bc_company_id`

---

### invoice_vendor_mappings

**Purpose:** Map QR invoice data (debtor, IBAN, client number) to Business Central MANDAT/SOUS-MANDAT dimensions.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `company_id` | UUID | NO | - | FK to bc_companies |
| `vendor_name` | VARCHAR | NO | - | Creditor name from QR |
| `debtor_name` | VARCHAR | YES | - | Debtor name (our client) |
| `client_numero` | VARCHAR | YES | - | Client number from reference |
| `iban` | VARCHAR | YES | - | Creditor IBAN |
| `mandat_bc` | VARCHAR | NO | - | MANDAT dimension code |
| `sous_mandat_bc` | VARCHAR | YES | - | SOUS-MANDAT dimension code |
| `confidence` | NUMERIC | YES | `0.50` | Mapping confidence (0-1) |
| `usage_count` | INTEGER | YES | `1` | Times this mapping was used |
| `last_used` | TIMESTAMP | YES | `now()` | Last usage timestamp |
| `created_at` | TIMESTAMP | YES | `now()` | Record creation |
| `updated_at` | TIMESTAMP | YES | `now()` | Last modification |

**Indexes:**
- `invoice_vendor_mappings_pkey` - Primary key
- `invoice_vendor_mappings_company_debtor_unique` - Unique on `(company_id, debtor_name)`
- `idx_mapping_unique` - Unique on `(company_id, vendor_name, COALESCE(client_numero, ''))`
- `idx_mapping_company_vendor` - Lookup by company + vendor
- `idx_mapping_company_client` - Lookup by company + client_numero (partial)
- `idx_mapping_iban` - Lookup by IBAN (partial)
- `idx_mapping_confidence` - Sort by confidence DESC

**Key Logic:**
- `debtor_name` is the primary matching criterion (preferred over vendor_name)
- Confidence starts at 0.50, increases to 1.0 with validated usage
- High confidence (≥0.80) bypasses LLM API calls

---

### vendor_gl_mappings

**Purpose:** Map vendor + description keywords to G/L accounts for automatic line attribution.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `company_id` | UUID | YES | - | FK to bc_companies |
| `vendor_name` | VARCHAR | NO | - | Vendor name |
| `vendor_no` | VARCHAR(20) | YES | - | ★ BC Vendor number for API lookup |
| `description_keyword` | VARCHAR | NO | - | Keyword to match in description |
| `description_full` | TEXT | YES | - | ★ Full description for audit |
| `gl_account_no` | VARCHAR | NO | - | Target G/L account number |
| `mandat_code` | VARCHAR(20) | YES | - | ★ MANDAT dimension value |
| `sous_mandat_code` | VARCHAR(20) | YES | - | ★ SOUS-MANDAT dimension value |
| `source_document_no` | VARCHAR(20) | YES | - | ★ Origin invoice number |
| `confidence` | NUMERIC | YES | `0.90` | Mapping confidence |
| `usage_count` | INTEGER | YES | `1` | Usage counter |
| `last_used` | TIMESTAMP | YES | `now()` | Last usage |
| `created_at` | TIMESTAMP | YES | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMP | YES | `now()` | Last modification |

**Indexes:**
- `vendor_gl_mappings_pkey` - Primary key
- `vendor_gl_mappings_company_id_vendor_name_description_keywo_key` - Unique constraint
- `idx_vendor_gl_lookup` - Lookup by `(company_id, vendor_name)`
- `idx_vendor_gl_vendor_no` - ★ NEW: Lookup by `(company_id, vendor_no)`

**Key Logic:**
- Same vendor can map to different G/L accounts based on `description_keyword`
- RAG polling learns from posted invoices and populates this table
- New columns support dimension tracking and traceability

---

### pending_invoice_context

**Purpose:** Temporary storage for QR-extracted data awaiting BC invoice creation.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `payment_reference` | VARCHAR | NO | - | **Primary Key** - QR payment reference |
| `debtor_name` | VARCHAR | NO | - | Debtor name from QR |
| `vendor_name` | VARCHAR | YES | - | Creditor name |
| `created_at` | TIMESTAMP | YES | `now()` | Context creation time |

**Indexes:**
- `pending_invoice_context_pkey` - Primary key on `payment_reference`
- `idx_pending_context_created` - For cleanup of old records

**Key Logic:**
- Redis queue contains invoice payload; this table provides extended context
- Records are deleted after successful BC invoice creation
- TTL cleanup recommended for records older than 7 days

---

### sync_checkpoints

**Purpose:** Track polling progress for RAG synchronization from Business Central.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | SERIAL | NO | auto | Primary key |
| `sync_type` | VARCHAR(50) | NO | - | Sync identifier (unique) |
| `company_id` | UUID | YES | - | FK to bc_companies (optional) |
| `last_processed_at` | TIMESTAMPTZ | NO | `'1900-01-01'` | Last BC SystemModifiedAt processed |
| `last_document_no` | VARCHAR(20) | YES | - | Last document number processed |
| `records_processed` | INTEGER | YES | `0` | Records in last batch |
| `total_records_processed` | BIGINT | YES | `0` | Cumulative total |
| `last_error` | TEXT | YES | - | Last error message if any |
| `last_success_at` | TIMESTAMPTZ | YES | - | Last successful sync timestamp |
| `created_at` | TIMESTAMPTZ | YES | `now()` | Record creation |
| `updated_at` | TIMESTAMPTZ | YES | `now()` | Auto-updated on modification |

**Indexes:**
- `sync_checkpoints_pkey` - Primary key
- `sync_checkpoints_sync_type_key` - Unique on `sync_type`
- `idx_sync_checkpoints_type` - Fast lookup by type

**Pre-populated Data:**
```sql
sync_type = 'rag_posted_invoices', last_processed_at = '1900-01-01T00:00:00Z'
```

**Key Logic:**
- Polling workflow queries BC for records WHERE `SystemModifiedAt > last_processed_at`
- After processing, update `last_processed_at` to latest record's timestamp
- `updated_at` auto-updates via trigger

---

## Indexes

### Performance Indexes Summary

| Table | Index | Columns | Purpose |
|-------|-------|---------|---------|
| `bc_companies` | `bc_companies_bc_company_id_key` | `bc_company_id` | Unique lookup |
| `invoice_vendor_mappings` | `idx_mapping_company_vendor` | `company_id, vendor_name` | Primary lookup |
| `invoice_vendor_mappings` | `idx_mapping_company_client` | `company_id, client_numero` | Client-based lookup |
| `invoice_vendor_mappings` | `idx_mapping_iban` | `iban` | IBAN-based fallback |
| `invoice_vendor_mappings` | `idx_mapping_confidence` | `confidence DESC` | Prioritize high confidence |
| `vendor_gl_mappings` | `idx_vendor_gl_lookup` | `company_id, vendor_name` | Primary lookup |
| `vendor_gl_mappings` | `idx_vendor_gl_vendor_no` | `company_id, vendor_no` | ★ NEW: BC vendor lookup |
| `sync_checkpoints` | `idx_sync_checkpoints_type` | `sync_type` | Fast type lookup |

---

## Triggers & Functions

### update_sync_checkpoint_timestamp()

**Purpose:** Auto-update `updated_at` column on sync_checkpoints modifications.

```sql
CREATE OR REPLACE FUNCTION update_sync_checkpoint_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_checkpoints_updated
    BEFORE UPDATE ON sync_checkpoints
    FOR EACH ROW
    EXECUTE FUNCTION update_sync_checkpoint_timestamp();
```

---

## Migration History

### 2025-12-19: Phase 5 - RAG Polling Support

**001_create_sync_checkpoints.sql**
- Created `sync_checkpoints` table
- Added trigger for auto-updating `updated_at`
- Inserted initial checkpoint for `rag_posted_invoices`

**002_alter_vendor_gl_mappings.sql**
- Added `vendor_no` - BC vendor number for API integration
- Added `description_full` - Complete description for audit trail
- Added `mandat_code` - MANDAT dimension tracking
- Added `sous_mandat_code` - SOUS-MANDAT dimension tracking
- Added `source_document_no` - Traceability to source invoice
- Created index on `(company_id, vendor_no)`

---

## Usage Examples

### RAG Lookup Query (Invoice → MANDAT)

```sql
SELECT mandat_bc, sous_mandat_bc, confidence
FROM invoice_vendor_mappings
WHERE company_id = $1
  AND (
    debtor_name = $2
    OR client_numero = $3
    OR iban = $4
  )
ORDER BY confidence DESC
LIMIT 1;
```

### RAG Lookup Query (Vendor → G/L Account)

```sql
SELECT gl_account_no, mandat_code, sous_mandat_code, confidence
FROM vendor_gl_mappings
WHERE company_id = $1
  AND vendor_name = $2
  AND $3 ILIKE '%' || description_keyword || '%'
ORDER BY confidence DESC
LIMIT 1;
```

### Update Polling Checkpoint

```sql
UPDATE sync_checkpoints
SET 
    last_processed_at = $1,
    last_document_no = $2,
    records_processed = $3,
    total_records_processed = total_records_processed + $3,
    last_success_at = NOW()
WHERE sync_type = 'rag_posted_invoices';
```

### Auto-Learn: Increment Confidence

```sql
UPDATE vendor_gl_mappings
SET 
    confidence = LEAST(confidence + 0.02, 1.0),
    usage_count = usage_count + 1,
    last_used = NOW()
WHERE id = $1;
```

---

## Security Considerations

1. **Parameterized Queries**: Always use `$1, $2` placeholders, never string interpolation
2. **Company Isolation**: All queries must include `company_id` filter
3. **No PII Storage**: Only business data, no personal customer information
4. **GDPR Hosting**: Frankfurt region ensures EU data residency

---

*Documentation generated from Neon PostgreSQL introspection on 2025-12-19*
