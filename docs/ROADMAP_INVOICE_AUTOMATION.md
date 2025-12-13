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
| Phase 4 | Attribution automatique G/L Account | 🔄 En cours |

---

## 🏗️ Architecture Complète (Phase 4)

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

```sql
-- Table référence sociétés BC
bc_companies (
    id UUID PRIMARY KEY,
    bc_company_id VARCHAR(50) UNIQUE,  -- ID Business Central
    name VARCHAR(100),                  -- CIVAF, etc.
    tenant_id VARCHAR(50),
    environment VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
)

-- Table mappings debtor → mandat (Phase 3)
invoice_vendor_mappings (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES bc_companies(id),
    vendor_name VARCHAR(200),           -- SERAFE AG, etc.
    debtor_name VARCHAR(200),           -- David Esteves Beles (CLÉ PRINCIPALE)
    client_numero VARCHAR(50),          -- 602.201
    iban VARCHAR(34),                   -- CH893000520211491010B
    mandat_bc VARCHAR(20),              -- 93622
    sous_mandat_bc VARCHAR(20),
    confidence DECIMAL(3,2),            -- 0.00 à 1.00
    usage_count INTEGER DEFAULT 1,
    last_used TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(company_id, debtor_name)     -- Contrainte sur debtor_name
)

-- Table mappings vendor + description → G/L Account (Phase 4)
vendor_gl_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES bc_companies(id),
    vendor_name VARCHAR(200) NOT NULL,
    description_keyword VARCHAR(100) NOT NULL,  -- "Honoraires", "Débours"
    gl_account_no VARCHAR(20) NOT NULL,         -- "25 01 00 02" ou "6200"
    confidence DECIMAL(3,2) DEFAULT 0.90,
    usage_count INTEGER DEFAULT 1,
    last_used TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(company_id, vendor_name, description_keyword)
)

-- Index pour recherche rapide
CREATE INDEX idx_vendor_gl_lookup 
ON vendor_gl_mappings(company_id, vendor_name);

-- Table contexte temporaire (Phase 3)
pending_invoice_context (
    payment_reference VARCHAR(50) PRIMARY KEY,
    debtor_name VARCHAR(200) NOT NULL,
    vendor_name VARCHAR(200),
    created_at TIMESTAMP DEFAULT NOW()
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

## 🔄 Phase 4 : Attribution G/L Account

### Principe

Le compte comptable (G/L Account) dépend de :
- **vendor_name** : le fournisseur
- **description_keyword** : un mot-clé dans la description/libellé de la facture

Exemple : Une facture du CENTRE PATRONAL avec "Honoraires" dans la description → compte `25 01 00 02`

### Workflow 1 : RAG Lookup GL

Nouveau node ajouté après RAG Lookup Mandat :

```
[RAG Lookup Mandat] → [RAG Lookup GL] → [IF Confidence Mandat]
```

**Données propagées vers Redis :**

```json
{
  "vendorName": "CENTRE PATRONAL",
  "amount": "1500.00",
  "reference": "000000000000000000000000000",
  "mandat_bc": "93622",
  "rag_confidence": 0.95,
  "gl_account_no": "25 01 00 02",
  "gl_confidence": 0.90,
  "description": "Honoraires conseil juridique",
  "needs_review": false
}
```

### Workflow 3 : UPSERT GL Mapping

Après l'UPSERT du mapping mandat, on fait l'UPSERT du GL :

```sql
INSERT INTO vendor_gl_mappings (
    company_id,
    vendor_name,
    description_keyword,
    gl_account_no
)
SELECT 
    c.id,
    '{{ $json.body.vendorName }}',
    '{{ $json.body.lineDescription }}',
    '{{ $json.body.glAccountNo }}'
FROM bc_companies c
WHERE c.bc_company_id = 'd0854afd-fdb9-ef11-8a6a-7c1e5246cd4e'
  AND '{{ $json.body.glAccountNo }}' <> ''
ON CONFLICT (company_id, vendor_name, description_keyword)
DO UPDATE SET
    gl_account_no = EXCLUDED.gl_account_no,
    confidence = LEAST(1.0, vendor_gl_mappings.confidence + 0.05),
    usage_count = vendor_gl_mappings.usage_count + 1,
    last_used = NOW(),
    updated_at = NOW()
RETURNING *
```

### Extension AL : PostedInvoiceWebhook.al (v1.4.2.0)

```al
codeunit 50110 "Posted Invoice Webhook"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purch.-Post", 'OnAfterPostPurchaseDoc', '', false, false)]
    local procedure OnAfterPostPurchaseInvoice(...)
    var
        LineDescription: Text[100];
        LineGLAccountNo: Code[20];
    begin
        // ... existing code ...
        
        // Get first invoice line data
        PurchInvLine.SetRange("Document No.", PurchInvHdrNo);
        if PurchInvLine.FindFirst() then begin
            // Get line description
            LineDescription := PurchInvLine.Description;
            
            // Get G/L Account - only if line type is G/L Account
            // TODO: For Item lines, would need to lookup G/L from Item Posting Group
            if PurchInvLine.Type = PurchInvLine.Type::"G/L Account" then
                LineGLAccountNo := PurchInvLine."No.";
            
            // Get dimensions...
        end;

        // Build JSON payload with new fields
        JsonPayload.Add('lineDescription', LineDescription);
        JsonPayload.Add('glAccountNo', LineGLAccountNo);
        // ... rest of payload ...
    end;
}
```

**Payload JSON enrichi :**

```json
{
  "event": "invoice_posted",
  "invoiceNo": "FACTURE-001",
  "vendorNo": "V00123",
  "vendorName": "CENTRE PATRONAL",
  "vendorIBAN": "CH89...",
  "amount": 1500.00,
  "paymentReference": "000000000000000000000000000",
  "mandatCode": "93622",
  "sousMandatCode": "",
  "lineDescription": "Honoraires conseil juridique",
  "glAccountNo": "25 01 00 02",
  "postingDate": "2025-12-13"
}
```

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
| Workflow 2: BC Connector | 🔄 | Pop Redis + OAuth + Vendor + Invoice + Line avec GL |
| Workflow 3: RAG Learning | ✅ | Webhook BC → UPSERT Mandat + UPSERT GL → Cleanup |
| AL Extension v1.4.2.0 | 🔄 | APIs custom + PostedInvoiceWebhook avec GL |

---

## 🔗 Workflows n8n

| Workflow | URL Webhook | Description |
|----------|-------------|-------------|
| QR-Reader - LLM - Redis | /webhook/qr-reader | Extraction, RAG mandat + GL, mapping |
| BC Connector | (trigger Redis) | Création facture BC avec G/L Account |
| RAG Learning - Invoice Posted | /webhook/rag-learning | Auto-apprentissage mandat + GL |

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

---

## 🚀 Prochaines étapes

### Phase 4 (en cours)
- [x] Créer table `vendor_gl_mappings`
- [x] Ajouter node RAG Lookup GL au Workflow 1
- [x] Modifier node "Set Use RAG mandat" pour inclure gl_account_no
- [ ] Modifier Workflow 2 pour utiliser gl_account_no dans la ligne
- [ ] Mettre à jour extension AL (v1.4.2.0) avec lineDescription + glAccountNo
- [ ] Ajouter UPSERT GL au Workflow 3
- [ ] Test end-to-end Phase 4

### Améliorations futures
- [ ] Multi-sociétés : ajouter companyId dynamique dans le payload AL
- [ ] Monitoring : dashboard des mappings RAG et leur évolution
- [ ] Cleanup automatique : CRON pour supprimer les pending_invoice_context > 7 jours
- [ ] Gestion des erreurs : retry/dead letter queue si webhook échoue

---

*Dernière mise à jour : 2025-12-13*
