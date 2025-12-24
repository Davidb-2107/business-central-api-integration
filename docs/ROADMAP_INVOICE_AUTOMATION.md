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
| Phase 6 | Robustesse & Monitoring | 🚧 En cours |
| Phase 7 | Multi-sources & Triggers automatiques | 📋 Planifié |
| Phase 8 | Multi-tenant & Multi-sociétés | 📋 Planifié |
| Phase 9 | Intelligence améliorée | 📋 Planifié |
| Phase 10 | Interface utilisateur | 📋 Planifié |

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

## 🚧 Phase 6 : Robustesse & Monitoring (En cours)

### 6.1 Gestion des erreurs avancée

| Tâche | Description | Priorité | Statut |
|-------|-------------|----------|--------|
| Dead Letter Queue | Redis queue `invoices:failed` pour factures en erreur | Haute | 📋 |
| Retry automatique | 3 tentatives avec backoff exponentiel (1s, 5s, 30s) | Haute | 📋 |
| Logging erreurs Neon | Table `error_logs` pour traçabilité | Haute | 📋 |
| Alertes Slack/Email | Notification webhook si erreur critique | Moyenne | 📋 |

### 6.2 Monitoring & Métriques

| Tâche | Description | Priorité | Statut |
|-------|-------------|----------|--------|
| Table `processing_stats` | Compteurs factures/jour, taux succès RAG | Haute | 📋 |
| Dashboard n8n | Workflow dédié pour générer stats | Moyenne | 📋 |
| Alertes seuils | Notification si taux RAG miss > 30% | Moyenne | 📋 |

### 6.3 Maintenance automatique

| Tâche | Description | Priorité | Statut |
|-------|-------------|----------|--------|
| Cleanup pending_invoice_context | CRON suppression entrées > 7 jours | Haute | 📋 |
| Cleanup error_logs | CRON archivage logs > 30 jours | Basse | 📋 |
| Confidence decay | Diminuer confidence mappings non utilisés > 90 jours | Basse | 📋 |

### Architecture Phase 6

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GESTION DES ERREURS                                 │
│                                                                             │
│  [Workflow 1/2]                                                             │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────┐     ┌─────────────┐     ┌──────────────┐                      │
│  │ Erreur? │─YES─▶│ Retry (x3) │─FAIL─▶│ Dead Letter │                      │
│  └────┬────┘     │ 1s/5s/30s  │      │ Queue Redis │                      │
│       │          └─────────────┘      └──────┬───────┘                      │
│      NO                                      │                              │
│       │                                      ▼                              │
│       ▼                              ┌──────────────┐                      │
│  [Suite normale]                     │ Log to Neon │                      │
│                                      │ error_logs  │                      │
│                                      └──────┬───────┘                      │
│                                             │                              │
│                                             ▼                              │
│                                      ┌──────────────┐                      │
│                                      │ Alert Slack │                      │
│                                      └──────────────┘                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Schéma tables Phase 6

```sql
-- Table logs d'erreurs
CREATE TABLE error_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_name VARCHAR(100) NOT NULL,
    node_name VARCHAR(100),
    error_type VARCHAR(50),           -- 'BC_API', 'OCR', 'RAG', 'REDIS', 'LLM'
    error_message TEXT,
    error_stack TEXT,
    input_data JSONB,                 -- Données d'entrée pour debug
    retry_count INTEGER DEFAULT 0,
    resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_error_logs_created ON error_logs(created_at DESC);
CREATE INDEX idx_error_logs_unresolved ON error_logs(resolved) WHERE resolved = false;

-- Table statistiques de traitement
CREATE TABLE processing_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES bc_companies(id),
    stat_date DATE NOT NULL,
    invoices_processed INTEGER DEFAULT 0,
    invoices_success INTEGER DEFAULT 0,
    invoices_failed INTEGER DEFAULT 0,
    rag_hits INTEGER DEFAULT 0,        -- RAG trouvé avec confidence >= 0.8
    rag_misses INTEGER DEFAULT 0,      -- RAG non trouvé ou confidence < 0.8
    llm_calls INTEGER DEFAULT 0,
    avg_processing_time_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, stat_date)
);

CREATE INDEX idx_processing_stats_date ON processing_stats(stat_date DESC);
```

---

## 📋 Phase 7 : Multi-sources & Triggers automatiques (Planifié)

### 7.1 Sources d'entrée additionnelles

| Source | Implémentation | Complexité | Priorité |
|--------|----------------|------------|----------|
| 📁 Watch Folder | n8n Watch Folder node sur dossier réseau/NAS | Moyenne | Haute |
| 📧 Email IMAP | Extraction pièces jointes PDF automatique | Moyenne | Haute |
| ☁️ SharePoint/OneDrive | Microsoft Graph API trigger | Haute | Moyenne |
| 📱 API mobile | Endpoint REST pour app mobile scan | Basse | Basse |

### 7.2 Preprocessing PDF

| Tâche | Description |
|-------|-------------|
| PDF multi-pages | Splitter PDF → plusieurs images → OCR par page |
| Détection QR position | Identifier automatiquement où est le QR dans la page |
| Rotation auto | Corriger l'orientation avant OCR |
| Qualité image | Amélioration contraste/netteté pour meilleur OCR |

### Architecture Phase 7

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SOURCES D'ENTRÉE MULTIPLES                          │
│                                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐                    │
│  │📁 Folder │  │📧 Email  │  │☁️ Share- │  │📱 Mobile │                    │
│  │  Watch   │  │  IMAP    │  │  Point   │  │   API    │                    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘                    │
│       │             │             │             │                          │
│       └─────────────┴──────┬──────┴─────────────┘                          │
│                            │                                               │
│                            ▼                                               │
│                   ┌─────────────────┐                                      │
│                   │  Preprocessing  │                                      │
│                   │  - PDF split    │                                      │
│                   │  - QR detect    │                                      │
│                   │  - Rotation     │                                      │
│                   └────────┬────────┘                                      │
│                            │                                               │
│                            ▼                                               │
│                   [Workflow 1: QR-Reader]                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 Phase 8 : Multi-tenant & Multi-sociétés (Planifié)

### 8.1 Support multi-sociétés BC

| Tâche | Description |
|-------|-------------|
| Boucle multi-company | Workflow 4 itère sur toutes les companies actives |
| Détection auto société | Basée sur `debtorName`, IBAN, ou domaine email |
| Configuration par société | Seuils confidence, comptes G/L par défaut, alertes |
| Isolation données | Chaque société a ses propres mappings |

### 8.2 Multi-tenant (SaaS)

| Tâche | Description |
|-------|-------------|
| Row-level security | Isolation données par tenant dans PostgreSQL |
| Gestion credentials | Vault sécurisé pour OAuth tokens par tenant |
| Onboarding workflow | Processus automatisé d'ajout nouveau client |
| Billing integration | Compteurs d'utilisation pour facturation |

### Schéma multi-tenant

```sql
-- Ajout tenant_id pour isolation
ALTER TABLE bc_companies ADD COLUMN tenant_id UUID;
ALTER TABLE invoice_vendor_mappings ADD COLUMN tenant_id UUID;
ALTER TABLE vendor_gl_mappings ADD COLUMN tenant_id UUID;

-- Row-level security
ALTER TABLE invoice_vendor_mappings ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON invoice_vendor_mappings
    USING (tenant_id = current_setting('app.current_tenant')::UUID);
```

---

## 📋 Phase 9 : Intelligence améliorée (Planifié)

### 9.1 RAG avancé

| Amélioration | Description | Impact |
|--------------|-------------|--------|
| Fuzzy matching | Tolérance aux typos (Levenshtein distance) | +15% matches |
| Synonymes | Table de correspondances ("CENTRE PATRONAL" = "CP") | +10% matches |
| Embedding vectors | Recherche sémantique avec pgvector | +20% matches |
| Apprentissage négatif | Mémoriser les corrections pour éviter mêmes erreurs | -30% erreurs |

### 9.2 Validation intelligente

| Tâche | Description |
|-------|-------------|
| Détection doublons | Alerte si même `payment_reference` déjà traitée |
| Contrôle montants | Flag si montant > seuil configurable (ex: 50'000 CHF) |
| Cohérence G/L | Vérifier que le compte existe dans BC avant création |
| Anomalies fournisseur | Alerte si nouveau fournisseur avec montant élevé |

### Architecture recherche sémantique

```sql
-- Extension pgvector pour embeddings
CREATE EXTENSION IF NOT EXISTS vector;

-- Ajout colonne embedding
ALTER TABLE vendor_gl_mappings 
ADD COLUMN description_embedding vector(384);

-- Index pour recherche rapide
CREATE INDEX idx_description_embedding 
ON vendor_gl_mappings 
USING ivfflat (description_embedding vector_cosine_ops);

-- Recherche sémantique
SELECT gl_account_no, confidence,
       1 - (description_embedding <=> $1) as similarity
FROM vendor_gl_mappings
WHERE company_id = $2
ORDER BY description_embedding <=> $1
LIMIT 5;
```

---

## 📋 Phase 10 : Interface utilisateur (Planifié)

### 10.1 Dashboard de review

| Fonctionnalité | Description |
|----------------|-------------|
| Liste factures pending | Factures avec `needs_review: true` |
| Correction manuelle | Modifier mandat/G/L avant création BC |
| Validation batch | Approuver plusieurs factures d'un coup |
| Historique | Timeline des factures traitées avec statut |
| Recherche | Filtrer par fournisseur, date, montant, statut |

### 10.2 Administration

| Fonctionnalité | Description |
|----------------|-------------|
| Gestion mappings | CRUD sur `invoice_vendor_mappings` et `vendor_gl_mappings` |
| Import/Export CSV | Backup et migration des mappings |
| Statistiques | Graphiques d'utilisation, taux de succès, évolution |
| Logs viewer | Consultation des erreurs avec filtres |
| Configuration | Seuils, alertes, paramètres par société |

### Stack technique suggérée

| Composant | Technologie | Justification |
|-----------|-------------|---------------|
| Frontend | Next.js + Tailwind | React, SSR, moderne |
| Auth | NextAuth.js | OAuth2 Microsoft pour SSO avec BC |
| Backend | API Routes Next.js | Serverless, simple |
| Database | Neon PostgreSQL | Déjà en place |
| Hosting | Vercel | CI/CD automatique, preview deployments |

---

## 📊 Priorités des évolutions

```
Phase 6 (Robustesse)     ████████████████████ Priorité 1 - En cours
├── Dead Letter Queue
├── Retry automatique
├── Logging erreurs
├── Alertes critiques
└── Cleanup automatique

Phase 7 (Multi-sources)  ███████████████░░░░░ Priorité 2
├── Watch Folder
├── Email IMAP
└── PDF preprocessing

Phase 9 (Intelligence)   ██████████░░░░░░░░░░ Priorité 3
├── Fuzzy matching
├── Détection doublons
└── Validation montants

Phase 8 (Multi-tenant)   ██████░░░░░░░░░░░░░░ Priorité 4
├── Multi-sociétés BC
└── Row-level security

Phase 10 (UI)            ████░░░░░░░░░░░░░░░░ Priorité 5
├── Dashboard review
└── Administration
```

---

## 📁 Fichiers de migration

| Fichier | Description |
|---------|-------------|
| [`migrations/001_create_sync_checkpoints.sql`](../migrations/001_create_sync_checkpoints.sql) | Création table + trigger + checkpoint initial |
| [`migrations/002_alter_vendor_gl_mappings.sql`](../migrations/002_alter_vendor_gl_mappings.sql) | Ajout colonnes vendor_no, dimensions, traceability |
| `migrations/003_create_error_logs.sql` | 📋 Phase 6 - Table error_logs |
| `migrations/004_create_processing_stats.sql` | 📋 Phase 6 - Table processing_stats |

---

*Dernière mise à jour : 2025-12-23*
