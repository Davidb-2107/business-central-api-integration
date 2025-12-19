# RAG Polling Workflow - État et Debug en cours

**Date** : 2025-12-19  
**Workflow ID** : `0HxQZrWL9vWitBYq`  
**Nom** : RAG Polling - Posted Purchase Invoices

---

## Résumé

Workflow n8n qui poll les factures comptabilisées depuis Business Central pour alimenter automatiquement la table `vendor_gl_mappings` (RAG G/L Account attribution).

---

## 🎯 PROBLÈME RÉSOLU

### Encodage OData du champ `type`

Le champ `type` dans les lignes BC est encodé :

| Valeur BC | Valeur API OData |
|-----------|------------------|
| `G/L Account` | `G_x002F_L_x0020_Account` |
| `Item` | `Item` |

**Correction appliquée** : Dans le node "Is G/L Account Line?", utiliser `G_x002F_L_x0020_Account` au lieu de `G/L Account`.

---

## État actuel : WORKFLOW FONCTIONNEL

### ✅ Tous les noeuds validés

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
| Split Lines | ✅ | Lignes individuelles |
| Is G/L Account Line? | ✅ | Condition: `type == "G_x002F_L_x0020_Account"` |

---

## Structure d'une ligne BC (exemple)

```json
{
  "documentNo": "108219",
  "lineNo": 10000,
  "type": "G_x002F_L_x0020_Account",
  "no": "6510",
  "description": "Webhook",
  "quantity": 1,
  "directUnitCost": 44,
  "amount": 44,
  "shortcutDimension1Code": "754",
  "shortcutDimension2Code": "",
  "buyFromVendorNo": "20000",
  "systemModifiedAt": "2025-12-19T12:00:27.68Z"
}
```

### Mapping vers vendor_gl_mappings

| Champ BC | Colonne DB |
|----------|------------|
| `buyFromVendorNo` | `vendor_no` |
| Depuis invoice header | `vendor_name` |
| Premier mot de `description` | `description_keyword` |
| `description` | `description_full` |
| `no` | `gl_account_no` |
| `shortcutDimension1Code` | `mandat_code` |
| `shortcutDimension2Code` | `sous_mandat_code` |
| `documentNo` | `source_document_no` |

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
                                                                    │
                                                                    ▼
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

### Set - Capture Max Timestamp

| Champ | Valeur |
|-------|--------|
| `max_timestamp` | `{{ $json.value[0].systemModifiedAt }}` |
| `records_count` | `{{ $json.value.length }}` |
| `invoices` | `{{ $json.value }}` |

### Has New Invoices?

- Condition : `{{ $json.records_count }}` > `0`

### Split Invoices

- Field to split : `invoices`

### Split Lines

- Field to split : `value`
- Include fields : `vendorNumber, vendorName, number, postingDate, systemModifiedAt`

### Is G/L Account Line?

- Condition : `{{ $json.type }}` equals `G_x002F_L_x0020_Account`

### Extract Description Keyword (Code node)

```javascript
const description = $input.item.json.description || '';
const firstWord = description.split(/\s+/)[0].toLowerCase().trim();

const normalized = firstWord
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .replace(/[^a-z0-9]/gi, '');

return {
  json: {
    ...$input.item.json,
    descriptionKeyword: normalized || 'unknown',
    descriptionFull: description,
    extractedAt: new Date().toISOString()
  }
};
```

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
  '{{ $json.vendorName.replace(/'/g, "''") }}',
  '{{ $json.vendorNumber }}',
  '{{ $json.descriptionKeyword }}',
  '{{ $json.descriptionFull.replace(/'/g, "''") }}',
  '{{ $json.no }}',
  '{{ $json.shortcutDimension1Code || '' }}',
  '{{ $json.shortcutDimension2Code || '' }}',
  0.90,
  1,
  NOW(),
  '{{ $json.documentNo }}',
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

---

## Tables Neon PostgreSQL

### sync_checkpoints

```sql
SELECT * FROM sync_checkpoints WHERE sync_type = 'rag_posted_invoices';
```

| Champ | Valeur |
|-------|--------|
| last_processed_at | 2025-12-19T12:12:26.097Z |
| records_processed | 20 |
| total_records_processed | 40+ |

### vendor_gl_mappings

```sql
SELECT vendor_name, vendor_no, description_keyword, gl_account_no, mandat_code, confidence 
FROM vendor_gl_mappings 
ORDER BY created_at DESC;
```

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

*Document mis à jour - 2025-12-19 20:00*
