# 🛡️ Phase 6 : Robustesse & Monitoring - Guide d'implémentation

## Vue d'ensemble

Ce document détaille l'implémentation de la Phase 6 : gestion des erreurs, monitoring et maintenance automatique.

---

## 📊 Tables créées

### error_logs
Stocke toutes les erreurs de traitement pour debug et alertes.

```sql
-- Voir migrations/003_create_error_logs_stats.sql
```

### processing_stats
Statistiques quotidiennes agrégées par société.

```sql
-- Voir migrations/003_create_error_logs_stats.sql
```

---

## 🔧 Patterns d'implémentation n8n

### Pattern 1 : Error Handling avec IF Error

Ajouter après chaque node critique (OCR, API BC, LLM) :

```
[Node critique] → [IF Error] → [Log Error] → [Alerte Slack optionnel]
                      ↓
                 [Suite normale]
```

**Configuration du node IF Error :**
```javascript
// Condition pour détecter une erreur
{{ $json.error !== undefined || $json.statusCode >= 400 }}
```

### Pattern 2 : Logging d'erreur (Node PostgreSQL)

**Query :**
```sql
INSERT INTO error_logs (workflow_name, node_name, error_type, error_message, input_data, retry_count)
VALUES ($1, $2, $3, $4, $5::jsonb, $6)
RETURNING id
```

**Query Replacement :**
```javascript
{{ [
    'QR-Reader',                              // $1: workflow_name
    $prevNode.name,                           // $2: node_name
    'OCR',                                    // $3: error_type (OCR, BC_API, RAG, REDIS, LLM)
    $json.error || $json.message || 'Unknown error', // $4: error_message
    JSON.stringify($json),                    // $5: input_data
    0                                         // $6: retry_count
] }}
```

### Pattern 3 : Incrémenter les stats (Node PostgreSQL)

**Après traitement réussi avec RAG hit :**
```sql
INSERT INTO processing_stats (company_id, stat_date, invoices_processed, invoices_success, rag_hits)
SELECT id, CURRENT_DATE, 1, 1, 1
FROM bc_companies WHERE bc_company_id = $1
ON CONFLICT (company_id, stat_date) 
DO UPDATE SET 
    invoices_processed = processing_stats.invoices_processed + 1,
    invoices_success = processing_stats.invoices_success + 1,
    rag_hits = processing_stats.rag_hits + 1,
    updated_at = NOW()
```

**Après traitement avec LLM (RAG miss) :**
```sql
INSERT INTO processing_stats (company_id, stat_date, invoices_processed, invoices_success, rag_misses, llm_calls)
SELECT id, CURRENT_DATE, 1, 1, 1, 1
FROM bc_companies WHERE bc_company_id = $1
ON CONFLICT (company_id, stat_date) 
DO UPDATE SET 
    invoices_processed = processing_stats.invoices_processed + 1,
    invoices_success = processing_stats.invoices_success + 1,
    rag_misses = processing_stats.rag_misses + 1,
    llm_calls = processing_stats.llm_calls + 1,
    updated_at = NOW()
```

**Après échec :**
```sql
INSERT INTO processing_stats (company_id, stat_date, invoices_processed, invoices_failed)
SELECT id, CURRENT_DATE, 1, 1
FROM bc_companies WHERE bc_company_id = $1
ON CONFLICT (company_id, stat_date) 
DO UPDATE SET 
    invoices_processed = processing_stats.invoices_processed + 1,
    invoices_failed = processing_stats.invoices_failed + 1,
    updated_at = NOW()
```

---

## 🔄 Workflow Maintenance & Monitoring

### Configuration

| Paramètre | Valeur |
|-----------|--------|
| Trigger | Schedule (CRON) |
| Fréquence | Tous les jours à 02:00 |
| Expression CRON | `0 2 * * *` |

### Nodes à créer

#### 1. Cleanup pending_invoice_context (> 7 jours)

```sql
DELETE FROM pending_invoice_context
WHERE created_at < NOW() - INTERVAL '7 days'
RETURNING payment_reference
```

#### 2. Archiver error_logs (> 30 jours)

```sql
-- Option 1: Marquer comme archivés
UPDATE error_logs 
SET resolved = true, resolved_at = NOW()
WHERE created_at < NOW() - INTERVAL '30 days'
  AND resolved = false
RETURNING id

-- Option 2: Supprimer (si pas besoin d'historique)
DELETE FROM error_logs
WHERE created_at < NOW() - INTERVAL '30 days'
  AND resolved = true
RETURNING id
```

#### 3. Générer rapport quotidien

```sql
SELECT 
    c.name as company,
    ps.stat_date,
    ps.invoices_processed,
    ps.invoices_success,
    ps.invoices_failed,
    ps.rag_hits,
    ps.rag_misses,
    CASE 
        WHEN ps.rag_hits + ps.rag_misses > 0 
        THEN ROUND(100.0 * ps.rag_hits / (ps.rag_hits + ps.rag_misses), 1)
        ELSE 0 
    END as rag_hit_rate_pct,
    ps.llm_calls
FROM processing_stats ps
JOIN bc_companies c ON ps.company_id = c.id
WHERE ps.stat_date = CURRENT_DATE - INTERVAL '1 day'
ORDER BY c.name
```

#### 4. Vérifier erreurs critiques (dernières 24h)

```sql
SELECT 
    error_type,
    COUNT(*) as error_count,
    MAX(created_at) as last_occurrence
FROM error_logs
WHERE created_at > NOW() - INTERVAL '24 hours'
  AND resolved = false
GROUP BY error_type
ORDER BY error_count DESC
```

#### 5. Alerte Slack (optionnel)

Si erreurs critiques > 5, envoyer alerte Slack :

```javascript
// Webhook URL à configurer
const webhookUrl = 'https://hooks.slack.com/services/XXX/YYY/ZZZ';

const message = {
    text: `⚠️ *Alerte Invoice Automation*\n\nErreurs détectées dans les dernières 24h:\n${$json.errors.map(e => `- ${e.error_type}: ${e.error_count}`).join('\n')}`
};
```

---

## 📈 Vues pour Dashboard

### v_recent_errors
Erreurs non résolues des dernières 24h.

```sql
SELECT * FROM v_recent_errors;
```

### v_weekly_stats
Statistiques de la semaine avec taux de succès RAG.

```sql
SELECT * FROM v_weekly_stats;
```

---

## 🎯 Nodes à modifier dans Workflow 1 (QR-Reader)

### Ajouts recommandés

| Position | Node à ajouter | Type | Description |
|----------|----------------|------|-------------|
| Après OCR | IF OCR Error | IF | Vérifie si OCR a échoué |
| Après IF OCR Error (true) | Log OCR Error | PostgreSQL | Log l'erreur dans error_logs |
| Après RAG Lookup | Rien | - | Déjà alwaysOutputData:true |
| Après LLM | IF LLM Error | IF | Vérifie si LLM a échoué |
| Après IF LLM Error (true) | Log LLM Error | PostgreSQL | Log l'erreur |
| Après Redis Push | Update Stats Success | PostgreSQL | Incrémente stats succès |
| Branche erreur | Update Stats Failed | PostgreSQL | Incrémente stats échec |

### Exemple de condition IF Error

```javascript
// Pour HTTP Request
{{ $json.error !== undefined || ($json.statusCode && $json.statusCode >= 400) }}

// Pour Node qui peut être vide
{{ !$json || Object.keys($json).length === 0 }}
```

---

## 🔔 Configuration Alertes (optionnel)

### Slack Webhook

1. Créer une app Slack : https://api.slack.com/apps
2. Activer Incoming Webhooks
3. Créer un webhook pour le channel souhaité
4. Stocker l'URL dans `app_config` :

```sql
INSERT INTO app_config (config_key, config_value, description)
VALUES ('slack_webhook_url', 'https://hooks.slack.com/services/...', 'Webhook pour alertes Slack')
ON CONFLICT (config_key) DO UPDATE SET config_value = EXCLUDED.config_value;
```

### Seuils d'alerte

| Métrique | Seuil | Action |
|----------|-------|--------|
| Erreurs / 24h | > 5 | Alerte Slack |
| Taux RAG miss | > 30% | Alerte Slack |
| Factures failed | > 10% | Alerte Slack |

---

## ✅ Checklist d'implémentation

### Base de données
- [x] Créer table `error_logs`
- [x] Créer table `processing_stats`
- [x] Créer fonction `increment_processing_stat`
- [x] Créer vue `v_recent_errors`
- [x] Créer vue `v_weekly_stats`

### Workflow Maintenance
- [ ] Créer workflow "Maintenance & Monitoring"
- [ ] Node CRON trigger (02:00 daily)
- [ ] Node Cleanup pending_invoice_context
- [ ] Node Archiver error_logs
- [ ] Node Générer rapport
- [ ] Node Vérifier erreurs critiques
- [ ] Node Alerte Slack (optionnel)

### Workflow QR-Reader (modifications)
- [ ] Ajouter IF Error après OCR
- [ ] Ajouter Log Error OCR
- [ ] Ajouter IF Error après LLM  
- [ ] Ajouter Log Error LLM
- [ ] Ajouter Update Stats Success
- [ ] Ajouter Update Stats Failed

### Workflow BC Connector (modifications)
- [ ] Ajouter IF Error après API BC
- [ ] Ajouter Log Error BC_API
- [ ] Ajouter Dead Letter Queue (Redis)
- [ ] Ajouter Update Stats

---

## 📝 Notes importantes

1. **Ordre des nodes** : Les nodes de stats doivent être APRÈS le succès confirmé (Redis push OK)

2. **Dead Letter Queue** : Utiliser une liste Redis séparée `invoices:failed` pour les factures en erreur

3. **Retry** : Implémenter le retry avec backoff exponentiel dans un workflow séparé qui lit `invoices:failed`

4. **GDPR** : Les `input_data` dans error_logs peuvent contenir des données sensibles - prévoir purge régulière

---

*Créé : 2025-12-24*
