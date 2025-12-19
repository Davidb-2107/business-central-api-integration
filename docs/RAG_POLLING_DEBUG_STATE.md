# RAG Polling Workflow - Documentation Complète

**Date** : 2025-12-19  
**Workflow ID** : `0HxQZrWL9vWitBYq`  
**Nom** : RAG Polling - Posted Purchase Invoices  
**Status** : ✅ **FONCTIONNEL EN PRODUCTION**

---

## Résumé

Workflow n8n qui poll les factures comptabilisées depuis Business Central pour alimenter automatiquement la table `vendor_gl_mappings` (RAG G/L Account attribution).

**Résultats** : 11 lignes G/L traitées, 9 mappings uniques créés avec UPSERT.

---

## 🎯 PROBLÈMES RÉSOLUS

### 1. Encodage OData du champ `type`

| Valeur BC | Valeur API OData |
|-----------|------------------|
| `G/L Account` | `G_x002F_L_x0020_Account` |
| `Item` | `Item` |

### 2. Structure imbriquée après Split Lines

L'API retourne les données dans un objet `value`, donc tous les champs doivent être accédés via `$json.value.*` :

```json
{
  "@odata.context": "...",
  "value": {
    "type": "G_x002F_L_x0020_Account",
    "no": "6510",
    "description": "Webhook",
    ...
  }
}
```

### 3. Code node en mode batch

Le noeud "Extract Description Keyword" doit traiter tous les items avec `$input.all()`, pas seulement le premier.

---

## État actuel : WORKFLOW FONCTIONNEL ✅

### Tous les noeuds validés

| Noeud | Status | Output |
|-------|--------|--------|
| Every 5 Minutes | ✅ | Trigger CRON |
| Get Checkpoint | ✅ | `last_processed_at` depuis sync_checkpoints |
| Get Token OAuth 2.0 | ✅ | Token BC valide |
| BC - Get Posted Invoices | ✅ | 20 factures (108201-108220) |
| Set - Capture Max Timestamp | ✅ | `max_timestamp`, `records_count`, `invoices` |
| Update Checkpoint Simple | ✅ | Checkpoint mis à jour |
| Has New Invoices? | ✅ | Condition sur `records_count > 0` |
| Split Invoices | ✅ | 20 items individuels |
| BC - Get Invoice Lines | ✅ | 20 appels API, lignes récupérées |
| Split Lines | ✅ | 20 lignes (Include: All Other Fields) |
| Is G/L Account Line? | ✅ | 11 true / 9 false |
| Extract Description Keyword | ✅ | 11 items avec keywords extraits |
| UPSERT vendor_gl_mappings | ✅ | 11 insertions/updates |
| Aggregate Results | ✅ | Agrégation des résultats |
| Calculate New Checkpoint | ✅ | Nouveau timestamp calculé |

---

## Structure d'une ligne BC (exemple)

```json
{
  "@odata.context": "https://api.businesscentral.dynamics.com/...",
  "value": {
    "@odata.etag": "W/\"...\"",
    "id": "d3978d39-feb9-f011-af69-6045bde99e23",
    "documentNo": "108220",
    "lineNo": 10000,
    "type": "G_x002F_L_x0020_Account",
    "no": "6510",
    "description": "Webhook",
    "description2": "",
    "quantity": 1,
    "directUnitCost": 44,
    "lineAmount": 44,
    "amount": 44,
    "amountIncludingVAT": 44,
    "unitOfMeasureCode": "",
    "shortcutDimension1Code": "752",
    "shortcutDimension2Code": "",
    "dimensionSetID": 23,
    "genBusPostingGroup": "EU",
    "genProdPostingGroup": "HANDEL",
    "vatBusPostingGroup": "EU",
    "vatProdPostingGroup": "BETRIEB",
    "buyFromVendorNo": "30000",
    "systemModifiedAt": "2025-12-19T12:12:25.883Z"
  }
}
```

### Mapping vers vendor_gl_mappings

| Champ BC | Colonne DB | Accès |
|----------|------------|-------|
| `value.buyFromVendorNo` | `vendor_no` | `$json.value.buyFromVendorNo` |
| `value.buyFromVendorNo` | `vendor_name` | (temporaire, à améliorer) |
| Premier mot de `value.description` | `description_keyword` | Extrait par Code node |
| `value.description` | `description_full` | `$json.descriptionFull` |
| `value.no` | `gl_account_no` | `$json.value.no` |
| `value.shortcutDimension1Code` | `mandat_code` | `$json.value.shortcutDimension1Code` |
| `value.shortcutDimension2Code` | `sous_mandat_code` | `$json.value.shortcutDimension2Code` |
| `value.documentNo` | `source_document_no` | `$json.value.documentNo` |

---

## Architecture du workflow

```
[Every 5 Min] → [Get Checkpoint] → [OAuth] → [BC - Get Posted Invoices]
                                                      │
                                                      ▼
                                        [Set - Capture Max Timestamp]
                                                      │
                              ┌───────────────────────┼───────────────────────┐
                              ▼                                               ▼
                   [Update Checkpoint Simple]                      [Has New Invoices?]
                              │                                               │
                             FIN                                    ┌────────┴────────┐
                                                                    ▼                 ▼
                                                             [Split Invoices]   [No New Invoices]
                                                                    │                  │
                                                                    ▼                 FIN
                                                           [BC - Get Invoice Lines]
                                                                    │
                                                                    ▼
                                                              [Split Lines]
                                                                    │
                                                                    ▼
                                                           [Is G/L Account Line?]
                                                                    │
                                                        ┌───────────┴───────────┐
                                                        ▼                       ▼
                                              [Extract Description]    [Skip Non-GL Lines]
                                                   (11 items)              (9 items)
                                                        │
                                                        ▼
                                              [UPSERT vendor_gl_mappings]
                                                        │
                                                        ▼
                                               [Aggregate Results]
                                                        │
                                                        ▼
                                            [Calculate New Checkpoint]
                                                        │
                                                       FIN
```

---

## Configuration des noeuds clés

### Split Lines

| Paramètre | Valeur |
|-----------|--------|
| Field to Split Out | `value` |
| Include | **All Other Fields** |

> ⚠️ Important : "All Other Fields" est nécessaire pour conserver `type`, `no`, `description`, etc.

### Is G/L Account Line?

| Paramètre | Valeur |
|-----------|--------|
| Left Value | `{{ $json.value.type }}` |
| Operation | `equals` |
| Right Value | `G_x002F_L_x0020_Account` |

> ⚠️ Important : Accéder via `$json.value.type` (pas `$json.type`)

### Extract Description Keyword (Code node)

```javascript
// Extract first word from description for keyword matching
const items = $input.all();
const results = [];

for (const item of items) {
  const description = item.json.value.description || '';
  const firstWord = description.split(/\s+/)[0].toLowerCase().trim();

  // Normalize: remove accents, special chars
  const normalized = firstWord
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/gi, '');

  results.push({
    json: {
      ...item.json,
      descriptionKeyword: normalized || 'unknown',
      descriptionFull: description,
      extractedAt: new Date().toISOString()
    }
  });
}

return results;
```

> ⚠️ Important : Utiliser `$input.all()` et boucler sur tous les items

### UPSERT vendor_gl_mappings

```sql
INSERT INTO vendor_gl_mappings (
  company_id,
  vendor_name,
  vendor_no,
  description_keyword,
  description_full,
  gl_account_no,
  mandat_code,
  sous_mandat_code,
  confidence,
  usage_count,
  last_used,
  source_document_no,
  created_at,
  updated_at
)
VALUES (
  (SELECT id FROM bc_companies LIMIT 1),
  '{{ ($json.value.buyFromVendorNo || "").replace(/'/g, "''") }}',
  '{{ $json.value.buyFromVendorNo || "" }}',
  '{{ $json.descriptionKeyword }}',
  '{{ ($json.descriptionFull || "").replace(/'/g, "''") }}',
  '{{ $json.value.no || "" }}',
  '{{ $json.value.shortcutDimension1Code || "" }}',
  '{{ $json.value.shortcutDimension2Code || "" }}',
  0.90,
  1,
  NOW(),
  '{{ $json.value.documentNo || "" }}',
  NOW(),
  NOW()
)
ON CONFLICT (company_id, vendor_name, description_keyword)
DO UPDATE SET
  vendor_no = EXCLUDED.vendor_no,
  gl_account_no = EXCLUDED.gl_account_no,
  mandat_code = EXCLUDED.mandat_code,
  sous_mandat_code = EXCLUDED.sous_mandat_code,
  description_full = EXCLUDED.description_full,
  usage_count = vendor_gl_mappings.usage_count + 1,
  confidence = LEAST(0.99, vendor_gl_mappings.confidence + 0.02),
  last_used = NOW(),
  source_document_no = EXCLUDED.source_document_no,
  updated_at = NOW()
RETURNING *;
```

> ⚠️ Important : Tous les champs BC via `$json.value.*`, les champs extraits via `$json.descriptionKeyword`

---

## Résultats en base de données

### sync_checkpoints

```sql
SELECT * FROM sync_checkpoints WHERE sync_type = 'rag_posted_invoices';
```

| Champ | Valeur |
|-------|--------|
| last_processed_at | 2025-12-19T12:12:26.097Z |
| records_processed | 20 |
| total_records_processed | 60+ |

### vendor_gl_mappings (9 enregistrements)

| vendor_name | description_keyword | gl_account_no | mandat_code | confidence |
|-------------|---------------------|---------------|-------------|------------|
| 30000 | webhook | 6510 | 752 | 0.94 |
| 20000 | webhook | 6510 | 754 | 0.90 |
| V00060 | test | 6510 | 763 | 0.90 |
| 20000 | periode | 6510 | 754 | 0.90 |
| V00070 | fonds | 6510 | 764 | 0.90 |
| V00080 | test | 6510 | 763 | 0.90 |
| V00070 | laje | 50 04 00 02 | 783 | 0.90 |
| V00060 | centre | 6510 | 763 | 0.94 |
| 64000 | ausgaben | 60410 | - | 0.90 |

---

## API Business Central utilisées

| Endpoint | Usage |
|----------|-------|
| `customPostedPurchaseInvoices` | Liste des factures comptabilisées |
| `customPostedPurchaseInvoiceLines` | Lignes d'une facture (filtré par documentNo) |

### Query parameters

```
$filter=systemModifiedAt gt {checkpoint}
$orderby=systemModifiedAt desc
$top=20
```

---

## Credentials

- **Neon Project ID** : `dawn-frog-92063130`
- **BC Tenant** : `5f225b4a-2f9e-4ba9-8863-ec7e18049f48`
- **BC Company ID** : `207217f3-fdb9-f011-af69-6045bde99e23`
- **BC Environment** : `sandbox`

---

## Encodages OData à retenir

| Caractère | Encodage OData |
|-----------|----------------|
| `/` | `_x002F_` |
| ` ` (espace) | `_x0020_` |
| `'` | `_x0027_` |

Donc `G/L Account` devient `G_x002F_L_x0020_Account` dans l'API.

---

## Améliorations futures

1. **vendor_name** : Actuellement contient `buyFromVendorNo`. À améliorer pour récupérer le vrai nom depuis le header de facture via Split Lines.

2. **Gestion multi-lignes** : Certaines factures peuvent avoir plusieurs lignes G/L - déjà géré par le workflow.

3. **Confidence decay** : Implémenter une diminution de confiance pour les mappings non utilisés.

---

*Document mis à jour - 2025-12-19 21:50*
