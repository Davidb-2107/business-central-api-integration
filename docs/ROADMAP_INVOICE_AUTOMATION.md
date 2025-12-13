# 🧾 Invoice Automation - Roadmap & Documentation

## Vue d'ensemble

Automatisation du traitement des factures QR suisses vers Microsoft Dynamics 365 Business Central.

**Objectif** : Éliminer la saisie manuelle en scannant les PDF, extrayant les données de paiement et créant automatiquement les factures d'achat avec les bonnes dimensions analytiques.

---

## 📊 Statut des Phases

| Phase | Description | Statut |
|-------|-------------|--------|
| Phase 1 | Infrastructure de base + intégration BC | ✅ Complète |
| Phase 2 | RAG intelligent pour mapping mandats | ✅ Complète |
| Phase 3 | Feedback loop auto-apprentissage | ✅ Complète |

---

## 🏗️ Architecture Complète (Phase 3)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  [PDF Facture]                                                              │
│       │                                                                     │
│       ▼                                                                     │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ WORKFLOW 1: QR-Reader - LLM - Redis                                  │   │
│  │                                                                      │   │
│  │  [Webhook] → [OCR Tesseract] → [Regex] → [INSERT Pending Context]   │   │
│  │                                                 │                    │   │
│  │                                                 ▼                    │   │
│  │  [RAG Lookup] ──► confidence ≥ 0.8 ──► [Set RAG Data] ──┐           │   │
│  │       │                                                  │           │   │
│  │       └──► confidence < 0.8 ──► [LLM Infomaniak] ──► [Set] ──► [Redis]  │
│  └──────────────────────────────────────────────────────────────────────┘   │
│             │                                                               │
│             ▼                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ WORKFLOW 2: BC Connector                                             │   │
│  │                                                                      │   │
│  │  [Redis Pop] → [OAuth2] → [Vendor] → [Invoice] → [Line + Dimensions] │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│             │                                                               │
│             ▼                                                               │
│  [Facture créée dans BC - brouillon]                                        │
│             │                                                               │
│             │ 👤 Utilisateur vérifie/corrige/POSTE                          │
│             ▼                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ WORKFLOW 3: RAG Learning - Invoice Posted                            │   │
│  │                                                                      │   │
│  │  [Webhook BC] → [Has Mandat?] → [UPSERT RAG + DELETE Context] → [OK] │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│             │                                                               │
│             ▼                                                               │
│  [Base RAG enrichie] ←─── Prochaine facture même debtor = skip LLM 🚀      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Principe clé : debtor_name → mandat_bc

Le mapping RAG est basé sur le **debtor_name** (nom du débiteur sur la facture), pas le vendor_name.

Ceci permet de gérer le cas où plusieurs sociétés partagent un même compte bancaire :

| debtor_name | mandat_bc |
|-------------|-----------|
| David Esteves Beles | 93622 |
| Jean Dupont | 764 |
| Autre Société SA | 765 |

Un même fournisseur (ex: CENTRE PATRONAL) peut facturer différents mandats selon le debtor_name.

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

-- Table contexte temporaire (Phase 3)
pending_invoice_context (
    payment_reference VARCHAR(50) PRIMARY KEY,
    debtor_name VARCHAR(200) NOT NULL,
    vendor_name VARCHAR(200),
    created_at TIMESTAMP DEFAULT NOW()
)
```

### Requête RAG Lookup

```sql
SELECT mandat_bc, sous_mandat_bc, confidence, usage_count
FROM invoice_vendor_mappings m
JOIN bc_companies c ON m.company_id = c.id
WHERE c.bc_company_id = 'd0854afd-fdb9-ef11-8a6a-7c1e5246cd4e'
  AND m.debtor_name ILIKE '%{{ $json.parsedData.debtorName }}%'
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

## 🔄 Phase 3 : Auto-apprentissage

### Flux complet

1. **Extraction** : debtor_name extrait par OCR, stocké dans `pending_invoice_context`
2. **Création BC** : Facture créée en brouillon
3. **Validation** : Utilisateur vérifie/corrige le mandat et **poste** la facture
4. **Webhook AL** : Trigger `OnAfterPostPurchaseDoc` envoie les données vers n8n
5. **UPSERT RAG** : Le mapping `debtor_name → mandat_bc` est créé/mis à jour
6. **Cleanup** : L'entrée `pending_invoice_context` est supprimée

### Extension AL : PostedInvoiceWebhook.al

```al
codeunit 50110 "Posted Invoice Webhook"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purch.-Post", 'OnAfterPostPurchaseDoc', '', false, false)]
    local procedure OnAfterPostPurchaseInvoice(...)
    begin
        // Envoie webhook vers https://hen8n.com/webhook/rag-learning
        // Payload: invoiceNo, vendorNo, vendorName, mandatCode, sousMandatCode, paymentReference
    end;
}
```

### Requête UPSERT (Workflow 3)

```sql
WITH context AS (
    SELECT debtor_name, vendor_name 
    FROM pending_invoice_context 
    WHERE payment_reference = '{{ $json.body.paymentReference }}'
),
upsert AS (
    INSERT INTO invoice_vendor_mappings (
        company_id, debtor_name, vendor_name, mandat_bc, sous_mandat_bc, confidence
    )
    SELECT 
        c.id,
        ctx.debtor_name,
        ctx.vendor_name,
        '{{ $json.body.mandatCode }}',
        '{{ $json.body.sousMandatCode }}',
        0.9
    FROM bc_companies c, context ctx
    WHERE c.bc_company_id = 'd0854afd-fdb9-ef11-8a6a-7c1e5246cd4e'
    ON CONFLICT (company_id, debtor_name)
    DO UPDATE SET
        mandat_bc = EXCLUDED.mandat_bc,
        sous_mandat_bc = EXCLUDED.sous_mandat_bc,
        vendor_name = EXCLUDED.vendor_name,
        confidence = LEAST(1.0, invoice_vendor_mappings.confidence + 0.05),
        usage_count = invoice_vendor_mappings.usage_count + 1,
        last_used = NOW(),
        updated_at = NOW()
    RETURNING *
)
DELETE FROM pending_invoice_context 
WHERE payment_reference = '{{ $json.body.paymentReference }}'
```

### Évolution de la confidence

| Événement | Confidence |
|-----------|------------|
| Premier mapping créé | 0.90 |
| 2ème validation | 0.95 |
| 3ème validation | 1.00 (max) |

---

## 📦 Composants opérationnels

| Composant | Statut | Description |
|-----------|--------|-------------|
| QR-reader | ✅ | App web Vercel, décode QR Swiss, envoie vers n8n |
| Tesseract OCR | ✅ | Container Docker VPS, API REST port 5000 |
| Regex extraction | ✅ | Patterns pour code_mandat, numero_facture, libelle |
| RAG Lookup | ✅ | Neon PostgreSQL, recherche par debtor_name |
| Infomaniak LLM | ✅ | Fallback si RAG < 0.8 (llama3, hébergé Suisse) |
| Redis Queue | ✅ | Découplage Extraction ↔ BC Connector |
| Workflow 1: Extraction | ✅ | OCR + Pending Context + RAG + LLM fallback + Redis |
| Workflow 2: BC Connector | ✅ | Pop Redis + OAuth + Vendor + Invoice + Dimensions |
| Workflow 3: RAG Learning | ✅ | Webhook BC → UPSERT RAG → Cleanup |
| AL Extension v1.4.1.0 | ✅ | APIs custom + PostedInvoiceWebhook trigger |

---

## 🔗 Workflows n8n

| Workflow | URL Webhook | Description |
|----------|-------------|-------------|
| QR-Reader - LLM - Redis | /webhook/qr-reader | Extraction et mapping |
| BC Connector | (trigger Redis) | Création facture BC |
| RAG Learning - Invoice Posted | /webhook/rag-learning | Auto-apprentissage |

---

## 📅 Historique des tests

| Date | Test | Résultat |
|------|------|----------|
| 2025-12-11 | SERAFE AG Phase 1 (sans RAG) | ✅ Facture créée, mandat 93622 |
| 2025-12-12 | SERAFE AG Phase 2 (avec RAG) | ✅ RAG trouve, LLM skipé |
| 2025-12-12 | CENTRE PATRONAL webhook AL | ✅ Webhook reçu dans n8n |
| 2025-12-12 | Phase 3 UPSERT + cleanup | ✅ confidence 0.90→0.95, pending supprimé |

---

## 🚀 Prochaines étapes (Phase 4 - Optionnel)

- [ ] Multi-sociétés : ajouter companyId dynamique dans le payload AL
- [ ] Monitoring : dashboard des mappings RAG et leur évolution
- [ ] Cleanup automatique : CRON pour supprimer les pending_invoice_context > 7 jours
- [ ] Gestion des erreurs : retry/dead letter queue si webhook échoue

---

*Dernière mise à jour : 2025-12-12*
