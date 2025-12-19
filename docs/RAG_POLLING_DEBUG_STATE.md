# RAG Polling Workflow - État et Debug en cours

**Date** : 2025-12-19  
**Workflow ID** : `0HxQZrWL9vWitBYq`  
**Nom** : RAG Polling - Posted Purchase Invoices

---

## Résumé

Workflow n8n qui poll les factures comptabilisées depuis Business Central pour alimenter automatiquement la table `vendor_gl_mappings` (RAG G/L Account attribution).

---

## État actuel : DEBUG EN COURS

### ✅ Noeuds validés

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

### 🔄 À valider

| Noeud | Action |
|-------|--------|
| Split Lines | Vérifier que les lignes sont splittées correctement |
| Is G/L Account Line? | Vérifier la condition `type == "G/L Account"` |
| Extract Description Keyword | Vérifier l'extraction du keyword |
| UPSERT vendor_gl_mappings | Vérifier l'insertion en DB |

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

- Condition : `{{ $json.type }}` equals `G/L Account`

---

## Problème potentiel à investiguer

Dans le noeud **"Is G/L Account Line?"**, vérifier :

1. **Le champ `type` existe-t-il ?** - Afficher l'output de "Split Lines" pour voir la structure
2. **Quelle est la valeur de `type` ?** - Peut-être `"G/L Account"` ou `"GL Account"` ou autre
3. **Y a-t-il des lignes G/L dans les factures testées ?** - Les factures 108211-108220 devraient en avoir

### Debug : Output attendu de "Split Lines"

```json
{
  "documentNo": "108211",
  "lineNo": 10000,
  "type": "G/L Account",    // <-- CE CHAMP EST CRITIQUE
  "no": "6200",             // Numéro de compte G/L
  "description": "Honoraires conseil",
  "quantity": 1,
  "unitPrice": 18250,
  "amount": 18250,
  "shortcutDimension1Code": "93622",
  "shortcutDimension2Code": "",
  ...
}
```

---

## Tables Neon PostgreSQL

### sync_checkpoints (état actuel)

```sql
SELECT * FROM sync_checkpoints WHERE sync_type = 'rag_posted_invoices';
```

| Champ | Valeur |
|-------|--------|
| last_processed_at | 2025-12-19T12:12:26.097Z |
| records_processed | 20 |
| total_records_processed | 40+ |

### vendor_gl_mappings (à peupler)

```sql
SELECT * FROM vendor_gl_mappings;
-- Actuellement vide - sera peuplé quand le workflow fonctionne
```

---

## Prochaines étapes

1. **Afficher l'output de "Split Lines"** pour voir la structure des lignes
2. **Vérifier le champ `type`** dans les lignes BC
3. **Ajuster la condition** si le champ a un nom différent
4. **Valider l'UPSERT** dans vendor_gl_mappings
5. **Tester le workflow complet**

---

## API Business Central utilisées

| Endpoint | Usage |
|----------|-------|
| `customPostedPurchaseInvoices` | Liste des factures comptabilisées |
| `customPostedPurchaseInvoiceLines` | Lignes d'une facture (filtré par documentNo) |

### Query parameters actuels

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

*Document créé pour continuité de debug - 2025-12-19*
