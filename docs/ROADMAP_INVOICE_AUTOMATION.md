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
| Phase 5 | RAG Polling depuis Posted Invoices | ✅ Complète |

---

## 🎉 Système Complet - Boucle d'Auto-Apprentissage

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BOUCLE D'AUTO-APPRENTISSAGE                         │
│                                                                             │
│  ┌─────────────────┐                                                        │
│  │  PDF Facture QR │                                                        │
│  └────────┬────────┘                                                        │
│           │                                                                 │
│           ▼                                                                 │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │ WORKFLOW 1: QR-Reader - LLM - Redis                                │     │
│  │                                                                    │     │
│  │  [Webhook] → [OCR] → [Regex] → [RAG Lookup Mandat]                │     │
│  │                                       │                            │     │
│  │                                       ▼                            │     │
│  │                              [RAG Lookup GL] ◄──────────────────┐  │     │
│  │                                       │                         │  │     │
│  │                                       ▼                         │  │     │
│  │                              [IF Confidence ≥ 0.8]              │  │     │
│  │                                   /       \                     │  │     │
│  │                                 OUI       NON                   │  │     │
│  │                                  │         │                    │  │     │
│  │                            [Use RAG]  [LLM Fallback]            │  │     │
│  │                                  │         │                    │  │     │
│  │                                  └────┬────┘                    │  │     │
│  │                                       ▼                         │  │     │
│  │                          [Redis Push] → [Pending Context]       │  │     │
│  └───────────────────────────────────────┼─────────────────────────┘  │     │
│                                          │                            │     │
│                                          ▼                            │     │
│  ┌────────────────────────────────────────────────────────────────┐  │     │
│  │ WORKFLOW 2: BC Connector                                       │  │     │
│  │                                                                │  │     │
│  │  [Redis Pop] → [OAuth2] → [Create Vendor] → [Create Invoice]  │  │     │
│  │                                    │                           │  │     │
│  │                                    ▼                           │  │     │
│  │                      [Add Line with G/L + Dimensions]          │  │     │
│  └────────────────────────────────────┼───────────────────────────┘  │     │
│                                       │                              │     │
│                                       ▼                              │     │
│                    [Facture brouillon dans BC]                       │     │
│                                       │                              │     │
│                          👤 Utilisateur POSTE                        │     │
│                                       │                              │     │
│                                       ▼                              │     │
│  ┌────────────────────────────────────────────────────────────────┐  │     │
│  │ WORKFLOW 4: RAG Polling - Posted Purchase Invoices             │  │     │
│  │                                                                │  │     │
│  │  [CRON 5min] → [Get Checkpoint] → [Query BC API]              │  │     │
│  │                                         │                      │  │     │
│  │                                         ▼                      │  │     │
│  │                          [Filter systemModifiedAt > checkpoint]│  │     │
│  │                                         │                      │  │     │
│  │                                         ▼                      │  │     │
│  │  [Split Invoices] → [Get Lines] → [Enrich with Header]        │  │     │
│  │                                         │                      │  │     │
│  │                                         ▼                      │  │     │
│  │                    [Filter G/L Account Lines Only]             │  │     │
│  │                                         │                      │  │     │
│  │                                         ▼                      │  │     │
│  │             [Extract Description Keyword] → [UPSERT]───────────┼──┘     │
│  │                                         │                      │        │
│  │                                         ▼                      │        │
│  │                           [Update Checkpoint]                  │        │
│  └─────────────────────────────────────────────────────────────────┘        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Principe de la boucle

1. **Nouvelle facture** → Workflow 1 cherche dans RAG
2. **RAG trouve** (confidence ≥ 0.8) → Utilise les valeurs, skip LLM
3. **RAG ne trouve pas** → LLM extrait les infos
4. **Facture créée** → Workflow 2 crée dans BC
5. **Utilisateur poste** → Facture devient "Posted Purchase Invoice"
6. **RAG Polling** → Workflow 4 capte la facture postée, extrait les mappings
7. **UPSERT** → `vendor_gl_mappings` enrichie, confidence augmente
8. **Prochaine facture** → RAG trouve avec meilleure confiance

**Plus le système traite de factures, plus il devient intelligent !** 🧠

---

## 🏗️ Architecture Technique

### Principes de mapping

| Mapping | Clé | Valeur | Table |
|---------|-----|--------|-------|
| Mandat | `debtor_name` | `mandat_bc`, `sous_mandat_bc` | `invoice_vendor_mappings` |
| G/L Account | `vendor_name` + `description_keyword` | `gl_account_no`, `mandat_code` | `vendor_gl_mappings` |

### Exemple de mappings Mandat

| debtor_name | mandat_bc | sous_mandat_bc |
|-------------|-----------|----------------|
| Caisse d'allocations familiales | 754 | |
| Caisse Intercorporative vaudoise | 783 | |
| SERAFE AG | 93622 | |

### Exemple de mappings G/L

| vendor_name | description_keyword | gl_account_no | mandat_code |
|-------------|---------------------|---------------|-------------|
| Graphic Design Institute | webhook | 6510 | 752 |
| First Up Consultants | periode | 6510 | 754 |
| CENTRE PATRONAL | centre | 6510 | 763 |
| Fonds de surcompensation | laje | 50 04 00 02 | 783 |

---

## 🔍 RAG Lookup Mandat - Détail technique

### Objectif

Trouver le code mandat Business Central à partir du nom du débiteur. Le matching se fait sur `debtor_name` (et non `vendor_name`) car plusieurs entreprises peuvent partager le même compte bancaire - c'est le débiteur (celui qui paie) qui détermine le code mandat.

**Exemple :**
| debtor_name | mandat_bc |
|-------------|-----------|
| Caisse d'allocations familiales | 754 |
| Caisse Intercorporative vaudoise | 783 |

### Requête SQL

```sql
SELECT mandat_bc, sous_mandat_bc, confidence, usage_count
FROM invoice_vendor_mappings m
JOIN bc_companies c ON m.company_id = c.id
WHERE c.bc_company_id = $1
  AND m.debtor_name ILIKE '%' || $2 || '%'
ORDER BY confidence DESC, usage_count DESC
LIMIT 1
```

### Paramètres SQL (queryReplacement)

```
$1 = bc_company_id
     → Filtre par société Business Central
     → Source: Get Config

$2 = parsedData.debtorName
     → Nom du débiteur extrait du QR-code
     → Source: Code in JavaScript - Regex
```

### Expression n8n (queryReplacement)

```javascript
{{ $('Get Config').item.json.config.bc_company_id }},{{ $json.parsedData.debtorName }}
```

### Sortie

| Champ | Description |
|-------|-------------|
| `mandat_bc` | Code mandat BC (ex: "754") |
| `sous_mandat_bc` | Sous-mandat (optionnel) |
| `confidence` | Score de confiance 0-1 (ex: 0.90) |
| `usage_count` | Nombre d'utilisations |

### Décision (IF Confidence Mandat)

| Confidence | Action | needs_review |
|------------|--------|--------------|
| ≥ 0.8 | Utiliser valeurs RAG, **skip LLM** | false |
| < 0.8 | Appeler LLM Infomaniak | true |

### Auto-apprentissage

- Le score de confiance s'incrémente à chaque validation (0.90 → 0.95 → 1.0)
- Le `usage_count` permet de prioriser les mappings les plus fréquents

---

## 🔍 RAG Lookup GL - Détail technique

### Objectif

Trouver le compte G/L approprié basé sur le fournisseur **ET** le type de dépense. Un même fournisseur peut facturer différents services qui vont sur **différents comptes G/L**.

**Exemple :**
| vendor_name | Description facture | description_keyword | gl_account_no |
|-------------|---------------------|---------------------|---------------|
| CENTRE PATRONAL | Cotisation AVS 2025 | cotisation | 5700 (charges sociales) |
| CENTRE PATRONAL | Formation sécurité | formation | 6510 (formation) |
| CENTRE PATRONAL | Assurance RC | assurance | 6300 (assurances) |

### Requête SQL

```sql
SELECT 
    gl_account_no, 
    confidence as gl_confidence, 
    usage_count as gl_usage_count,
    description_keyword
FROM vendor_gl_mappings m
JOIN bc_companies c ON m.company_id = c.id
WHERE c.bc_company_id = $1
  AND m.vendor_name ILIKE '%' || $2 || '%'
  AND $3 ILIKE '%' || m.description_keyword || '%'
ORDER BY confidence DESC, usage_count DESC
LIMIT 1
```

### Paramètres SQL (queryReplacement)

```
$1 = bc_company_id
     → Filtre par société Business Central
     → Source: Get Config

$2 = parsedData.companyName
     → Nom du fournisseur extrait du QR-code
     → Source: Code in JavaScript - Regex

$3 = Description (avec fallback)
     → 1. regexResults.libelle (ex: "Cotisation LAJE")
     → 2. ocrText (500 premiers chars si libelle vide)
     → 3. '' (chaîne vide en dernier recours)
     → Source: Code in JavaScript - Regex
```

### Expression n8n (queryReplacement)

```javascript
{{ $('Get Config').item.json.bc_company_id }}, {{ $('Code in JavaScript - Regex').item.json.parsedData.companyName }}, {{ $('Code in JavaScript - Regex').item.json.regexResults.libelle || $('Code in JavaScript - Regex').item.json.ocrText.substring(0, 500) || '' }}
```

### Logique de fallback pour $3

| Priorité | Source | Exemple |
|----------|--------|---------|
| 1 | `regexResults.libelle` | "Cotisation LAJE" |
| 2 | `ocrText` (500 chars) | Texte OCR si libelle vide |
| 3 | `''` | Chaîne vide (évite erreurs null) |

### Sortie

| Champ | Description |
|-------|-------------|
| `gl_account_no` | Numéro du compte G/L (ex: "6510") |
| `gl_confidence` | Score de confiance 0-1 (ex: 0.90) |
| `gl_usage_count` | Nombre d'utilisations |
| `description_keyword` | Mot-clé qui a matché |

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
    vendor_no VARCHAR(20),
    description_keyword VARCHAR(100) NOT NULL,
    description_full TEXT,
    gl_account_no VARCHAR(20) NOT NULL,
    mandat_code VARCHAR(20),
    sous_mandat_code VARCHAR(20),
    source_document_no VARCHAR(20),
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

-- Table checkpoints polling (Phase 5)
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
    updated_at TIMESTAMPTZ DEFAULT NOW()
)
```

### Logique de décision

| Confidence | Action | needs_review |
|------------|--------|--------------|
| ≥ 0.8 | Utiliser valeurs RAG, **skip LLM** | false |
| < 0.8 | Appeler LLM Infomaniak | true |
| Pas de résultat | Appeler LLM Infomaniak | true |

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
| Workflow 1: QR-Reader | ✅ | OCR + RAG Mandat + RAG GL + LLM fallback + Redis |
| Workflow 2: BC Connector | ✅ | Pop Redis + OAuth + Vendor + Invoice + Line avec GL |
| Workflow 3: RAG Learning | ✅ | Webhook BC → UPSERT Mandat + UPSERT GL → Cleanup |
| **Workflow 4: RAG Polling** | ✅ | CRON 5min → Query BC → UPSERT GL avec dimensions |
| AL Extension v1.4.2.0 | ✅ | APIs custom + PostedInvoiceWebhook avec GL |

---

## 🔗 Workflows n8n

| Workflow | ID | Trigger | Description |
|----------|-----|---------|-------------|
| QR-Reader - LLM - Redis | I4jxZ9oILeuIMrYS | Webhook `/qr-reader` | Extraction, RAG mandat + GL, mapping |
| BC Connector | - | Redis RPOP | Création facture BC avec G/L Account |
| RAG Learning - Invoice Posted | - | Webhook `/rag-learning` | Auto-apprentissage via webhook BC |
| **RAG Polling - Posted Invoices** | 0HxQZrWL9vWitBYq | CRON 5min | Apprentissage via polling API BC |

### Documentation détaillée Workflow 4

> 📄 **Documentation complète** : [RAG_POLLING_DEBUG_STATE.md](RAG_POLLING_DEBUG_STATE.md)

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
| 2025-12-19 | Phase 5 - Workflow RAG Polling | ✅ 20 factures traitées |
| 2025-12-19 | Phase 5 - Enrich Lines with Header | ✅ vendorName propagé |
| 2025-12-19 | Phase 5 - UPSERT vendor_gl_mappings | ✅ 9 mappings créés |
| 2025-12-19 | Phase 5 - Gestion "No New Invoices" | ✅ COALESCE/NULLIF |
| 2025-12-23 | RAG Lookup GL - Fix paramètre $3 | ✅ Utilise regexResults.libelle avec fallback |
| 2025-12-23 | Documentation RAG Lookup Mandat | ✅ Sticky Note + ROADMAP |

---

## ✅ Tâches complétées Phase 5

- [x] Créer table `sync_checkpoints`
- [x] Ajouter colonnes à `vendor_gl_mappings` (vendor_no, mandat_code, etc.)
- [x] Créer index sur `(company_id, vendor_no)`
- [x] Documenter schéma dans DATABASE_SCHEMA.md
- [x] Créer Workflow 4 : RAG Polling
- [x] Configurer query BC API customPostedPurchaseInvoices
- [x] Configurer query BC API customPostedPurchaseInvoiceLines
- [x] Implémenter Enrich Lines with Header (vendorName)
- [x] Implémenter boucle UPSERT avec dimensions
- [x] Gérer cas "No New Invoices" (timestamp null)
- [x] Test end-to-end Phase 5

---

## 🚀 Améliorations futures

- [ ] Multi-sociétés : boucle sur toutes les companies dans sync_checkpoints
- [ ] Monitoring : dashboard des mappings RAG et leur évolution
- [ ] Cleanup automatique : CRON pour supprimer les pending_invoice_context > 7 jours
- [ ] Gestion des erreurs : retry/dead letter queue si API BC échoue
- [ ] Webhooks + Polling : mode hybride pour redondance
- [ ] Confidence decay : diminuer la confiance des mappings non utilisés

---

## 📁 Fichiers de migration

| Fichier | Description |
|---------|-------------|
| [`migrations/001_create_sync_checkpoints.sql`](../migrations/001_create_sync_checkpoints.sql) | Création table + trigger + checkpoint initial |
| [`migrations/002_alter_vendor_gl_mappings.sql`](../migrations/002_alter_vendor_gl_mappings.sql) | Ajout colonnes vendor_no, dimensions, traceability |

---

*Dernière mise à jour : 2025-12-23*
