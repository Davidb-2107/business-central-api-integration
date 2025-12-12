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
| Phase 3 | Feedback loop auto-apprentissage | 🚧 En cours |

---

## 🏗️ Architecture Actuelle (Phase 2)

```
                                    ┌─ confidence ≥ 0.8 ─→ [Set RAG Data] ──┐
[Webhook] → [OCR] → [Regex] → [RAG Lookup] → [IF]                          ├→ [Redis] → [Response]
                                    └─ confidence < 0.8 ─→ [LLM] → [Set] ──┘
```

### Flux détaillé

1. **Webhook** reçoit les données QR + image de la facture
2. **OCR (Tesseract)** extrait le texte de l'image
3. **Regex** tente d'extraire code_mandat, numero_facture, libelle
4. **RAG Lookup** cherche un mapping connu dans Neon PostgreSQL
5. **IF** décide selon la confidence :
   - **≥ 0.8** : Utilise le mandat de la base RAG (LLM skipé ✅)
   - **< 0.8** : Appelle le LLM Infomaniak pour extraction
6. **Redis** stocke les données pour le workflow BC Connector

### Avantages du RAG avant LLM

- ⚡ **Performance** : Skip du LLM pour les fournisseurs connus
- 💰 **Économie** : Moins d'appels API Infomaniak
- 🎯 **Précision** : Le code mandat BC correct (93622) vs le code client (602.201)

---

## 🗄️ Base de données RAG (Neon PostgreSQL)

### Configuration

| Paramètre | Valeur |
|-----------|--------|
| Provider | Neon (Serverless PostgreSQL) |
| Région | Frankfurt (aws-eu-central-1) |
| Project ID | dawn-frog-92063130 |
| Database | neondb |

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

-- Table mappings fournisseur → mandat
invoice_vendor_mappings (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES bc_companies(id),
    vendor_name VARCHAR(200),           -- SERAFE AG, etc.
    debtor_name VARCHAR(200),           -- David Esteves Beles
    client_numero VARCHAR(50),          -- 602.201
    iban VARCHAR(34),                   -- CH893000520211491010B
    mandat_bc VARCHAR(20),              -- 93622
    sous_mandat_bc VARCHAR(20),
    confidence DECIMAL(3,2),            -- 0.00 à 1.00
    usage_count INTEGER DEFAULT 1,
    last_used TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(company_id, vendor_name, COALESCE(client_numero, ''))
)
```

### Critères de recherche RAG

Le RAG Lookup utilise **4 critères** pour trouver un mapping :

| Critère | Source | Exemple |
|---------|--------|---------|
| vendor_name | parsedData.vendorName | SERAFE AG |
| debtor_name | parsedData.debtorName | David Esteves Beles |
| client_numero | regexResults.code_mandat | 602.201 |
| iban | parsedData.iban | CH893000520211491010B |

**Requête SQL :**
```sql
SELECT mandat_bc, sous_mandat_bc, confidence, usage_count
FROM invoice_vendor_mappings m
JOIN bc_companies c ON m.company_id = c.id
WHERE c.bc_company_id = $1
  AND (
    m.vendor_name ILIKE '%' || $2 || '%'
    OR ($3 IS NOT NULL AND $3 != '' AND m.debtor_name ILIKE '%' || $3 || '%')
    OR ($4 IS NOT NULL AND $4 != '' AND m.client_numero = $4)
    OR ($5 IS NOT NULL AND $5 != '' AND m.iban = $5)
  )
ORDER BY confidence DESC, usage_count DESC
LIMIT 1;
```

### Logique de décision

| Confidence | Action | needs_review |
|------------|--------|--------------|
| ≥ 0.8 | Utiliser mandat RAG, **skip LLM** | false |
| < 0.8 | Appeler LLM Infomaniak | true |
| Pas de résultat | Appeler LLM Infomaniak | true |

---

## 📦 Composants opérationnels

| Composant | Statut | Description |
|-----------|--------|-------------|
| QR-reader | ✅ | App web Vercel, décode QR Swiss, envoie vers n8n |
| Tesseract OCR | ✅ | Container Docker VPS, API REST port 5000 |
| Regex extraction | ✅ | Patterns pour code_mandat, numero_facture, libelle |
| **RAG Lookup** | ✅ | Neon PostgreSQL, recherche multi-critères |
| Infomaniak LLM | ✅ | Fallback si RAG < 0.8 (llama3, hébergé Suisse) |
| Redis Queue | ✅ | Découplage Extraction ↔ BC Connector |
| Workflow Extraction | ✅ | OCR + RAG + LLM fallback + push Redis |
| Workflow BC Connector | ✅ | Pop Redis + OAuth + Vendor + Invoice + Dimensions |
| AL Extension BC | ✅ | APIs custom (Vendor, PurchaseInvoice, PurchaseLine) |

---

## 🔗 Credentials n8n

### Neon RAG Invoice (PostgreSQL)

| Paramètre | Valeur |
|-----------|--------|
| Host | ep-sweet-frost-ag3y4bjg-pooler.c-2.eu-central-1.aws.neon.tech |
| Database | neondb |
| User | neondb_owner |
| Port | 5432 |
| SSL | require |

---

## 📍 Chemins JSON - Référence

### Après node Webhook
```javascript
$json.body.parsedData.vendorName      // "SERAFE AG"
$json.body.parsedData.debtorName      // "David Esteves Beles"
$json.body.parsedData.amount          // "335.00"
$json.body.parsedData.iban            // "CH893000520211491010B"
$json.body.parsedData.reference       // "278600317270190039362280099"
```

### Après node Regex
```javascript
$json.parsedData.vendorName           // "SERAFE AG"
$json.parsedData.debtorName           // "David Esteves Beles"
$json.regexResults.code_mandat        // "602.201" (ou vide)
$json.parsedData.iban                 // "CH893000520211491010B"
```

### Après node RAG Lookup
```javascript
$json.mandat_bc                       // "93622"
$json.sous_mandat_bc                  // null
$json.confidence                      // 0.90
$json.usage_count                     // 1
```

### Après Set RAG Data (branche TRUE)
```javascript
$json.mandat_bc                       // "93622"
$json.needs_review                    // false
$json.rag_confidence                  // 0.90
```

---

## 🚀 Prochaines étapes (Phase 3)

### Feedback Loop

Quand une facture est validée dans BC, mettre à jour la base RAG :

```sql
INSERT INTO invoice_vendor_mappings (...)
ON CONFLICT (company_id, vendor_name, COALESCE(client_numero, ''))
DO UPDATE SET
    confidence = LEAST(1.0, confidence + 0.1),
    usage_count = usage_count + 1,
    last_used = NOW(),
    updated_at = NOW();
```

### Auto-apprentissage

1. Nouvelle facture → RAG ne trouve rien → LLM extrait
2. Utilisateur valide/corrige dans BC
3. Webhook BC → n8n met à jour la base RAG
4. Prochaine facture même fournisseur → RAG trouve directement

---

## 📅 Historique des tests

| Date | Test | Résultat |
|------|------|----------|
| 2025-12-11 | SERAFE AG Phase 1 (sans RAG) | ✅ Facture créée, mandat 93622 |
| 2025-12-12 | SERAFE AG Phase 2 (avec RAG) | ✅ RAG trouve, LLM skipé |

---

## 🔧 Configuration n8n - Nodes clés

### Node: RAG Lookup
- **Type**: PostgreSQL
- **Operation**: Execute Query
- **Credential**: Neon RAG Invoice
- **Query Parameters**: companyId, vendorName, debtorName, client_numero, iban

### Node: IF Confidence
- **Condition**: `{{ $json.confidence }}` >= 0.8
- **TRUE**: Set RAG Data → Redis
- **FALSE**: LLM → Set LLM Data → Redis

### Node: Set RAG Data
- **mandat_bc**: `{{ $('RAG Lookup').item.json.mandat_bc }}`
- **needs_review**: false
- **rag_confidence**: `{{ $('RAG Lookup').item.json.confidence }}`

---

*Dernière mise à jour : 2025-12-12*
