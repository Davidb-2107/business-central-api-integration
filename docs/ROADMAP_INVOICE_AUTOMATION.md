# 🧾 Invoice Automation - Roadmap & Documentation

## Vue d'ensemble

Automatisation du traitement des factures QR suisses vers Microsoft Dynamics 365 Business Central.

**Objectif** : Éliminer la saisie manuelle en scannant les PDF, extrayant les données de paiement et créant automatiquement les factures d'achat avec les bonnes dimensions analytiques et comptes comptables.

---

## 📊 Statut des Phases

| Phase | Description | Statut |
|-------|-------------|--------|
| Phase 1 | Infrastructure de base + intégration BC | ✅ Complète |
| Phase 2 | RAG intelligent pour mapping mandats | ✅ Complète |
| Phase 3 | Feedback loop auto-apprentissage | ✅ Complète |
| Phase 4 | Attribution automatique G/L Account | ✅ Complète |
| Phase 5 | RAG Polling depuis Posted Invoices | 🔄 En cours |

---

## 🏗️ Architecture Complète (Phase 5)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  [PDF Facture]                                                              │
│       │                                                                     │
│       ▼                                                                     │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ WORKFLOW 1: QR-Reader - LLM - Redis                                  │   │
│  │                                                                      │   │
│  │  [Webhook] → [OCR Tesseract] → [Regex]                              │   │
│  │                                   │                                  │   │
│  │                                   ▼                                  │   │
│  │  [RAG Lookup Mandat] → [RAG Lookup GL] → [IF Confidence]            │   │
│  │       │                      │                  │                    │   │
│  │       │                      │           ┌──────┴──────┐             │   │
│  │       │                      │           ▼             ▼             │   │
│  │       │                      │      [Set RAG]    [LLM Fallback]      │   │
│  │       │                      │           │             │             │   │
│  │       │                      │           └──────┬──────┘             │   │
│  │       │                      │                  ▼                    │   │
│  │       │                      │     [INSERT Pending] → [Redis Push]   │   │
│  └───────┴──────────────────────┴──────────────────────────────────────┘   │
│             │                                                               │
│             ▼                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ WORKFLOW 2: BC Connector                                             │   │
│  │                                                                      │   │
│  │  [Redis Pop] → [OAuth2] → [Vendor] → [Invoice] → [Line + GL + Dims]  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│             │                                                               │
│             ▼                                                               │
│  [Facture créée dans BC - brouillon avec G/L Account pré-rempli]           │
│             │                                                               │
│             │ 👤 Utilisateur vérifie/corrige/POSTE                          │
│             ▼                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ WORKFLOW 3: RAG Learning - Invoice Posted                            │   │
│  │                                                                      │   │
│  │  [Webhook BC] → [UPSERT Mandat] → [UPSERT GL] → [DELETE Context]     │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│             │                                                               │
│             ▼                                                               │
│  [Base RAG enrichie : mandat + G/L Account]                                │
│             │                                                               │
│             ▼ ★ NEW PHASE 5                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ WORKFLOW 4: RAG Polling (Alternative au Webhook)                     │   │
│  │                                                                      │   │
│  │  [CRON 5min] → [Get Checkpoint] → [Query BC Posted Invoices]        │   │
│  │       │                                │                             │   │
│  │       │                                ▼                             │   │
│  │       │           [Filter by SystemModifiedAt > last_processed_at]  │   │
│  │       │                                │                             │   │
│  │       │                                ▼                             │   │
│  │       │           [Loop Each Invoice] → [UPSERT GL Mapping]         │   │
│  │       │                                │                             │   │
│  │       │                                ▼                             │   │
│  │       └──────────────── [Update Checkpoint]                          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Principes clés

| Mapping | Clé | Valeur |
|---------|-----|--------|
| Mandat | `debtor_name` | `mandat_bc`, `sous_mandat_bc` |
| G/L Account | `vendor_name` + `description_keyword` | `gl_account_no` |

Le G/L Account dépend du fournisseur ET de la description de la prestation :

| vendor_name | description_keyword | gl_account_no |
|-------------|---------------------|---------------|
| CENTRE PATRONAL | Honoraires | 25 01 00 02 |
| CENTRE PATRONAL | Débours | 50 08 00 04 |
| SWISSCOM | Abonnement | 62 00 00 00 |

---

## 🗄️ Base de données RAG (Neon PostgreSQL)

### Configuration

| Paramètre | Valeur |
|-----------|--------|
| Provider | Neon (Serverless PostgreSQL) |
| Région | Frankfurt (aws-eu-central-1) |
| Project ID | dawn-frog-92063130 |
| Database | neondb |
| bc_company_id CIVAF | d0854afd-fdb9-ef11-8a6a-7c1e5246cd4e |

### Schéma

> 📄 **Documentation complète** : [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md)

```sql
-- Table référence sociétés BC
bc_companies (
    id UUID PRIMARY KEY,
    bc_company_id VARCHAR(50) UNIQUE,
    name VARCHAR(100),
    tenant_id VARCHAR(50),
    environment VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
)

-- Table mappings debtor → mandat (Phase 3)
invoice_vendor_mappings (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES bc_companies(id),
    vendor_name VARCHAR(200),
    debtor_name VARCHAR(200),           -- CLÉ PRINCIPALE
    client_numero VARCHAR(50),
    iban VARCHAR(34),
    mandat_bc VARCHAR(20),
    sous_mandat_bc VARCHAR(20),
    confidence DECIMAL(3,2),
    usage_count INTEGER DEFAULT 1,
    last_used TIMESTAMP,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    UNIQUE(company_id, debtor_name)
)

-- Table mappings vendor + description → G/L Account (Phase 4+5)
vendor_gl_mappings (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES bc_companies(id),
    vendor_name VARCHAR(200) NOT NULL,
    vendor_no VARCHAR(20),              -- ★ NEW Phase 5: BC Vendor No
    description_keyword VARCHAR(100) NOT NULL,
    description_full TEXT,              -- ★ NEW Phase 5: Full description
    gl_account_no VARCHAR(20) NOT NULL,
    mandat_code VARCHAR(20),            -- ★ NEW Phase 5: MANDAT dimension
    sous_mandat_code VARCHAR(20),       -- ★ NEW Phase 5: SOUS-MANDAT dimension
    source_document_no VARCHAR(20),     -- ★ NEW Phase 5: Source invoice
    confidence DECIMAL(3,2) DEFAULT 0.90,
    usage_count INTEGER DEFAULT 1,
    last_used TIMESTAMP,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    UNIQUE(company_id, vendor_name, description_keyword)
)

-- Table contexte temporaire (Phase 3)
pending_invoice_context (
    payment_reference VARCHAR(50) PRIMARY KEY,
    debtor_name VARCHAR(200) NOT NULL,
    vendor_name VARCHAR(200),
    created_at TIMESTAMP DEFAULT NOW()
)

-- ★ NEW Phase 5: Table checkpoints polling
sync_checkpoints (
    id SERIAL PRIMARY KEY,
    sync_type VARCHAR(50) UNIQUE NOT NULL,
    company_id UUID REFERENCES bc_companies(id),
    last_processed_at TIMESTAMPTZ NOT NULL DEFAULT '1900-01-01',
    last_document_no VARCHAR(20),
    records_processed INTEGER DEFAULT 0,
    total_records_processed BIGINT DEFAULT 0,
    last_error TEXT,
    last_success_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()  -- Auto-updated via trigger
)
```

### Requête RAG Lookup Mandat

```sql
SELECT mandat_bc, sous_mandat_bc, confidence, usage_count
FROM invoice_vendor_mappings m
JOIN bc_companies c ON m.company_id = c.id
WHERE c.bc_company_id = 'd0854afd-fdb9-ef11-8a6a-7c1e5246cd4e'
  AND m.debtor_name ILIKE '%{{ $json.parsedData.debtorName }}%'
ORDER BY confidence DESC, usage_count DESC
LIMIT 1
```

### Requête RAG Lookup GL (Phase 4)

```sql
SELECT 
    gl_account_no, 
    confidence as gl_confidence, 
    usage_count as gl_usage_count,
    description_keyword
FROM vendor_gl_mappings m
JOIN bc_companies c ON m.company_id = c.id
WHERE c.bc_company_id = 'd0854afd-fdb9-ef11-8a6a-7c1e5246cd4e'
  AND m.vendor_name ILIKE '%' || '{{ $json.parsedData.companyName }}' || '%'
  AND '{{ $json.parsedData.message }}' ILIKE '%' || m.description_keyword || '%'
ORDER BY confidence DESC, usage_count DESC
LIMIT 1
```

### Logique de décision

| Confidence | Action | needs_review |
|------------|--------|--------------|
| ≥ 0.8 | Utiliser mandat RAG, **skip LLM** | false |
| < 0.8 | Appeler LLM Infomaniak | true |
| Pas de résultat | Appeler LLM Infomaniak | true |

---

## 🔄 Phase 5 : RAG Polling depuis Posted Invoices

### Problématique

Le Workflow 3 (RAG Learning via Webhook BC) fonctionne, mais :
- Nécessite une extension AL avec événement OnAfterPost
- Dépend de la stabilité du webhook
- Pas de rattrapage si webhook manqué

### Solution : Polling API BC

Workflow 4 qui interroge périodiquement les factures comptabilisées via l'API BC standard.

### Table sync_checkpoints

```sql
-- Checkpoint initial
INSERT INTO sync_checkpoints (sync_type, last_processed_at)
VALUES ('rag_posted_invoices', '1900-01-01T00:00:00Z');
```

### Query BC Posted Purchase Invoices

```
GET /v2.0/{tenant}/Production/api/v2.0/companies({companyId})/purchaseInvoices
  ?$filter=status eq 'Paid' or status eq 'Open'
           and systemModifiedAt gt {last_processed_at}
  &$orderby=systemModifiedAt asc
  &$top=50
  &$expand=purchaseInvoiceLines
```

### Workflow 4 Structure

1. **Trigger** : CRON every 5 minutes
2. **Get Checkpoint** : Read `last_processed_at` from sync_checkpoints
3. **Query BC API** : Fetch invoices WHERE systemModifiedAt > checkpoint
4. **Loop Each Invoice** :
   - Extract vendor_name, vendor_no, line descriptions, G/L accounts, dimensions
   - UPSERT into vendor_gl_mappings with new columns
5. **Update Checkpoint** : Set `last_processed_at` = max(systemModifiedAt)

### Nouvelles colonnes vendor_gl_mappings

| Colonne | Usage |
|---------|-------|
| `vendor_no` | Lookup BC par numéro fournisseur |
| `description_full` | Description complète pour audit |
| `mandat_code` | Dimension MANDAT de la ligne |
| `sous_mandat_code` | Dimension SOUS-MANDAT |
| `source_document_no` | Numéro facture d'origine |

---

## 📦 Composants opérationnels

| Composant | Statut | Description |
|-----------|--------|-------------|
| QR-reader | ✅ | App web Vercel, décode QR Swiss, envoie vers n8n |
| Tesseract OCR | ✅ | Container Docker VPS, API REST port 5000 |
| Regex extraction | ✅ | Patterns pour code_mandat, numero_facture, libelle |
| RAG Lookup Mandat | ✅ | Neon PostgreSQL, recherche par debtor_name |
| RAG Lookup GL | ✅ | Neon PostgreSQL, recherche par vendor_name + description |
| Infomaniak LLM | ✅ | Fallback si RAG < 0.8 (llama3, hébergé Suisse) |
| Redis Queue | ✅ | Découplage Extraction ↔ BC Connector |
| Workflow 1: Extraction | ✅ | OCR + RAG Mandat + RAG GL + LLM fallback + Redis |
| Workflow 2: BC Connector | ✅ | Pop Redis + OAuth + Vendor + Invoice + Line avec GL |
| Workflow 3: RAG Learning | ✅ | Webhook BC → UPSERT Mandat + UPSERT GL → Cleanup |
| Workflow 4: RAG Polling | 🔄 | CRON → Query BC → UPSERT GL avec dimensions |
| AL Extension v1.4.2.0 | ✅ | APIs custom + PostedInvoiceWebhook avec GL |

---

## 🔗 Workflows n8n

| Workflow | Trigger | Description |
|----------|---------|-------------|
| QR-Reader - LLM - Redis | Webhook `/qr-reader` | Extraction, RAG mandat + GL, mapping |
| BC Connector | Redis RPOP | Création facture BC avec G/L Account |
| RAG Learning - Invoice Posted | Webhook `/rag-learning` | Auto-apprentissage via webhook BC |
| RAG Polling - Posted Invoices | CRON 5min | ★ NEW: Apprentissage via polling API BC |

---

## 📅 Historique des tests

| Date | Test | Résultat |
|------|------|----------|
| 2025-12-11 | SERAFE AG Phase 1 (sans RAG) | ✅ Facture créée, mandat 93622 |
| 2025-12-12 | SERAFE AG Phase 2 (avec RAG) | ✅ RAG trouve, LLM skipé |
| 2025-12-12 | CENTRE PATRONAL webhook AL | ✅ Webhook reçu dans n8n |
| 2025-12-12 | Phase 3 UPSERT + cleanup | ✅ confidence 0.90→0.95, pending supprimé |
| 2025-12-13 | Phase 4 - Table vendor_gl_mappings | ✅ Table créée dans Neon |
| 2025-12-13 | Phase 4 - RAG Lookup GL Workflow 1 | ✅ Node ajouté |
| 2025-12-19 | Phase 5 - Table sync_checkpoints | ✅ Table créée, trigger ajouté |
| 2025-12-19 | Phase 5 - ALTER vendor_gl_mappings | ✅ 5 colonnes ajoutées + index |

---

## 🚀 Prochaines étapes

### Phase 5 (en cours)
- [x] Créer table `sync_checkpoints`
- [x] Ajouter colonnes à `vendor_gl_mappings` (vendor_no, mandat_code, etc.)
- [x] Créer index sur `(company_id, vendor_no)`
- [x] Documenter schéma dans DATABASE_SCHEMA.md
- [ ] Créer Workflow 4 : RAG Polling
- [ ] Configurer query BC API Posted Invoices
- [ ] Implémenter boucle UPSERT avec dimensions
- [ ] Test end-to-end Phase 5

### Améliorations futures
- [ ] Multi-sociétés : boucle sur toutes les companies dans sync_checkpoints
- [ ] Monitoring : dashboard des mappings RAG et leur évolution
- [ ] Cleanup automatique : CRON pour supprimer les pending_invoice_context > 7 jours
- [ ] Gestion des erreurs : retry/dead letter queue si API BC échoue
- [ ] Webhooks + Polling : mode hybride pour redondance

---

## 📁 Fichiers de migration

| Fichier | Description |
|---------|-------------|
| [`migrations/001_create_sync_checkpoints.sql`](../migrations/001_create_sync_checkpoints.sql) | Création table + trigger + checkpoint initial |
| [`migrations/002_alter_vendor_gl_mappings.sql`](../migrations/002_alter_vendor_gl_mappings.sql) | Ajout colonnes vendor_no, dimensions, traceability |

---

*Dernière mise à jour : 2025-12-19*
