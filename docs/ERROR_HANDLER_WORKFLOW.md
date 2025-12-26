# 🛡️ Error Handler - Invoice Automation

## Vue d'ensemble

| Propriété | Valeur |
|-----------|--------|
| **ID** | `jh4umA1l7a7nYs1o` |
| **Nom** | Error Handler - Invoice Automation |
| **Type** | Error Workflow (déclenché automatiquement) |
| **Statut** | Inactif (pas besoin d'être actif) |
| **Créé** | 2025-12-26 |

## Objectif

Ce workflow centralise la gestion des erreurs pour tous les workflows de l'automation de factures. Il est déclenché automatiquement lorsqu'une erreur non gérée survient dans un workflow connecté.

**Workflows connectés :**
- ✅ Workflow 1 - QR-Reader - LLM - Redis
- ✅ Workflow 2 - Trigger -> to Business Central

## Architecture

```
┌─────────────────┐
│  Error Trigger  │ ← Déclenché automatiquement par n8n
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│  Log Error to Database  │ → INSERT INTO error_logs
└────────┬────────────────┘
         │
         ▼
┌─────────────────┐
│  Get Company ID │ → SELECT FROM bc_companies
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│  Update Stats Failed│ → UPSERT processing_stats
└────────┬────────────┘
         │
         ▼
┌──────────────────────────┐
│ Push to Dead Letter Queue│ → Redis invoices:failed
└────────┬─────────────────┘
         │
         ▼
┌─────────────────────────┐
│ Check Error Count (24h) │ → COUNT(*) error_logs
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ IF Critical (> 5 errors)│
└────────┬────────────────┘
         │
    ┌────┴────┐
    │  TRUE   │
    ▼         │
┌────────────────────┐    │
│ Format Slack Message│    │
└────────┬───────────┘    │
         │                │
         ▼                │
┌─────────────────┐       │
│ Send a message  │       │
│    (Slack)      │       │
└─────────────────┘       │
                          │
              FALSE ──────┘ (fin)
```

---

## Nodes détaillés

### 1. Error Trigger

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.errorTrigger` |
| **ID** | `c0ce2987-d901-4797-9bd7-410e04e1a0a4` |

**Données reçues automatiquement :**
```javascript
{
  "workflow": {
    "id": "xxx",
    "name": "Workflow 1 - QR-Reader - LLM - Redis"
  },
  "execution": {
    "id": "xxx",
    "startedAt": "2025-12-26T14:30:00.000Z",
    "mode": "trigger",
    "retryOf": null,
    "error": {
      "message": "Error message here",
      "stack": "Error stack trace...",
      "node": {
        "name": "HTTP Request - Tesseract OCR"
      }
    }
  }
}
```

---

### 2. Log Error to Database

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.postgres` |
| **ID** | `9ee7f71f-2c61-4ca4-b78e-1b5776a0c9fd` |
| **Credential** | Neon RAG Invoice |

**Query SQL :**
```sql
INSERT INTO error_logs (
    workflow_name, 
    node_name, 
    error_type, 
    error_message, 
    error_stack,
    input_data
)
VALUES ($1, $2, $3, $4, $5, $6::jsonb)
RETURNING id, workflow_name, error_type
```

**Query Replacement :**
```javascript
{{ [
    $json.workflow.name,
    $json.execution.error.node?.name || 'Unknown Node',
    $json.workflow.name.includes('QR-Reader') ? 'OCR' : 
    $json.workflow.name.includes('Trigger') ? 'BC_API' : 
    $json.workflow.name.includes('RAG') ? 'RAG' : 'UNKNOWN',
    $json.execution.error.message || 'No error message',
    $json.execution.error.stack || null,
    JSON.stringify({
        execution_id: $json.execution.id,
        workflow_id: $json.workflow.id,
        started_at: $json.execution.startedAt,
        mode: $json.execution.mode,
        retry_of: $json.execution.retryOf || null
    })
] }}
```

**Mapping error_type :**
| Workflow source | error_type |
|-----------------|------------|
| QR-Reader | `OCR` |
| Trigger (BC Connector) | `BC_API` |
| RAG | `RAG` |
| Autre | `UNKNOWN` |

---

### 3. Get Company ID

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.postgres` |
| **ID** | `23539c0b-60e6-4f4a-9155-e1000482e0c7` |

**Query SQL :**
```sql
SELECT id, bc_company_id 
FROM bc_companies 
LIMIT 1
```

> **Note :** Pour un système multi-tenant, cette query devra être adaptée pour extraire le company_id du contexte d'erreur.

---

### 4. Update Stats Failed

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.postgres` |
| **ID** | `3858bb79-5470-4e87-81a7-a6d9635d967a` |

**Query SQL :**
```sql
INSERT INTO processing_stats (company_id, stat_date, invoices_processed, invoices_failed)
VALUES ($1, CURRENT_DATE, 1, 1)
ON CONFLICT (company_id, stat_date) 
DO UPDATE SET 
    invoices_processed = processing_stats.invoices_processed + 1,
    invoices_failed = processing_stats.invoices_failed + 1,
    updated_at = NOW()
```

**Query Replacement :**
```javascript
{{ $('Get Company ID').item.json.id }}
```

---

### 5. Push to Dead Letter Queue

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.redis` |
| **ID** | `1fc0febd-2dae-4af6-b7ad-262e0fffce96` |
| **Credential** | Redis account |
| **Operation** | Push |
| **List** | `invoices:failed` |
| **Tail** | `true` (ajoute à la fin) |

**Data :**
```javascript
{{ JSON.stringify({
    timestamp: new Date().toISOString(),
    workflow: $('Error Trigger').item.json.workflow.name,
    execution_id: $('Error Trigger').item.json.execution.id,
    node: $('Error Trigger').item.json.execution.error.node?.name || 'Unknown',
    error: $('Error Trigger').item.json.execution.error.message,
    can_retry: true
}) }}
```

**Exemple de donnée stockée :**
```json
{
  "timestamp": "2025-12-26T14:35:00.000Z",
  "workflow": "Workflow 1 - QR-Reader - LLM - Redis",
  "execution_id": "12345",
  "node": "HTTP Request - Tesseract OCR",
  "error": "Connection timeout",
  "can_retry": true
}
```

---

### 6. Check Error Count (24h)

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.postgres` |
| **ID** | `c4ad500d-47cc-4418-a691-a9cb9c008524` |

**Query SQL :**
```sql
SELECT COUNT(*) as error_count
FROM error_logs
WHERE created_at > NOW() - INTERVAL '24 hours'
  AND resolved = false
```

---

### 7. IF Critical (> 5 errors)

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.if` |
| **ID** | `14eceb7d-90a8-4167-9e83-8e3bf52ec577` |

**Condition :**
```javascript
{{ $json.error_count > 5 }}
```

| Branche | Action |
|---------|--------|
| TRUE | Continue vers Format Slack Message |
| FALSE | Fin du workflow |

---

### 8. Format Slack Message

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.code` |
| **ID** | `7f56ea51-938a-4d0c-83aa-50830077cb31` |

**Code JavaScript :**
```javascript
const errorTrigger = $('Error Trigger').item.json;
const errorCount = $('Check Error Count (24h)').item.json.error_count;

const message = {
  text: `🚨 *Alerte Invoice Automation*`,
  blocks: [
    {
      type: "header",
      text: {
        type: "plain_text",
        text: "🚨 Erreur Invoice Automation"
      }
    },
    {
      type: "section",
      fields: [
        {
          type: "mrkdwn",
          text: `*Workflow:*\n${errorTrigger.workflow.name}`
        },
        {
          type: "mrkdwn",
          text: `*Node:*\n${errorTrigger.execution.error.node?.name || 'Unknown'}`
        }
      ]
    },
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: `*Erreur:*\n\`\`\`${errorTrigger.execution.error.message}\`\`\``
      }
    },
    {
      type: "context",
      elements: [
        {
          type: "mrkdwn",
          text: `⚠️ ${errorCount} erreurs dans les dernières 24h | Execution ID: ${errorTrigger.execution.id}`
        }
      ]
    }
  ]
};

return { message };
```

---

### 9. Send a message (Slack)

| Propriété | Valeur |
|-----------|--------|
| **Type** | `n8n-nodes-base.slack` |
| **ID** | `caaf6eed-359d-49a8-90f6-907454d8bc3b` |
| **Credential** | Slack account |
| **Channel** | `tous-n8n` (ID: `C09MT3L0CAG`) |

**Message :** `{{ $json.message }}`

---

## Tables PostgreSQL utilisées

### error_logs
```sql
CREATE TABLE error_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_name VARCHAR NOT NULL,
    node_name VARCHAR,
    error_type VARCHAR,           -- OCR, BC_API, RAG, UNKNOWN
    error_message TEXT,
    error_stack TEXT,
    input_data JSONB,
    retry_count INTEGER DEFAULT 0,
    resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### processing_stats
```sql
CREATE TABLE processing_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES bc_companies(id),
    stat_date DATE NOT NULL,
    invoices_processed INTEGER DEFAULT 0,
    invoices_success INTEGER DEFAULT 0,
    invoices_failed INTEGER DEFAULT 0,
    rag_hits INTEGER DEFAULT 0,
    rag_misses INTEGER DEFAULT 0,
    llm_calls INTEGER DEFAULT 0,
    UNIQUE(company_id, stat_date)
);
```

---

## Redis Dead Letter Queue

**Liste :** `invoices:failed`

**Commandes utiles :**
```bash
# Voir les erreurs en attente
redis-cli LRANGE invoices:failed 0 -1

# Compter les erreurs
redis-cli LLEN invoices:failed

# Retirer une erreur (pour retry manuel)
redis-cli LPOP invoices:failed
```

---

## Configuration des workflows sources

Pour connecter un workflow au Error Handler :

1. Ouvrir le workflow source
2. **Settings** (icône engrenage) → **Workflow Settings**
3. **Error Workflow** → Sélectionner `Error Handler - Invoice Automation`
4. Sauvegarder

---

## Monitoring & Debug

### Voir les erreurs récentes
```sql
SELECT * FROM v_recent_errors;
```

### Voir les stats hebdomadaires
```sql
SELECT * FROM v_weekly_stats;
```

### Erreurs par type (dernières 24h)
```sql
SELECT 
    error_type,
    COUNT(*) as count,
    MAX(created_at) as last_occurrence
FROM error_logs
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY error_type
ORDER BY count DESC;
```

---

## Améliorations futures

- [ ] Extraire le `company_id` du contexte d'erreur (multi-tenant)
- [ ] Ajouter un workflow de retry automatique depuis la Dead Letter Queue
- [ ] Configurer des seuils d'alerte personnalisables dans `app_config`
- [ ] Ajouter des alertes email en plus de Slack

---

*Documentation créée : 2025-12-26*
