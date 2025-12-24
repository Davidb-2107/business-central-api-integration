-- =====================================================
-- Migration 003: Phase 6 - Error Logs & Processing Stats
-- Date: 2025-12-24
-- Description: Tables pour gestion des erreurs et monitoring
-- =====================================================

-- ===========================================
-- 1. Table error_logs
-- ===========================================
-- Stocke toutes les erreurs de traitement pour debug et alertes

CREATE TABLE IF NOT EXISTS error_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_name VARCHAR(100) NOT NULL,     -- 'QR-Reader', 'BC Connector', etc.
    node_name VARCHAR(100),                   -- Nom du node n8n en erreur
    error_type VARCHAR(50),                   -- 'BC_API', 'OCR', 'RAG', 'REDIS', 'LLM'
    error_message TEXT,                       -- Message d'erreur
    error_stack TEXT,                         -- Stack trace complet
    input_data JSONB,                         -- Données d'entrée pour reproduire l'erreur
    retry_count INTEGER DEFAULT 0,            -- Nombre de tentatives effectuées
    resolved BOOLEAN DEFAULT false,           -- Erreur résolue manuellement ?
    resolved_at TIMESTAMPTZ,                  -- Date de résolution
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index pour requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_error_logs_created ON error_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_error_logs_unresolved ON error_logs(resolved) WHERE resolved = false;
CREATE INDEX IF NOT EXISTS idx_error_logs_type ON error_logs(error_type);

COMMENT ON TABLE error_logs IS 'Phase 6: Logs des erreurs de traitement pour debug et monitoring';

-- ===========================================
-- 2. Table processing_stats
-- ===========================================
-- Statistiques quotidiennes agrégées par société

CREATE TABLE IF NOT EXISTS processing_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES bc_companies(id),
    stat_date DATE NOT NULL,
    
    -- Compteurs factures
    invoices_processed INTEGER DEFAULT 0,     -- Total factures reçues
    invoices_success INTEGER DEFAULT 0,       -- Factures créées avec succès
    invoices_failed INTEGER DEFAULT 0,        -- Factures en erreur
    
    -- Compteurs RAG
    rag_hits INTEGER DEFAULT 0,               -- RAG trouvé (confidence >= 0.8)
    rag_misses INTEGER DEFAULT 0,             -- RAG non trouvé ou confidence < 0.8
    
    -- Compteurs LLM
    llm_calls INTEGER DEFAULT 0,              -- Appels LLM Infomaniak
    
    -- Performance
    avg_processing_time_ms INTEGER,           -- Temps moyen de traitement
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(company_id, stat_date)
);

CREATE INDEX IF NOT EXISTS idx_processing_stats_date ON processing_stats(stat_date DESC);
CREATE INDEX IF NOT EXISTS idx_processing_stats_company ON processing_stats(company_id, stat_date DESC);

COMMENT ON TABLE processing_stats IS 'Phase 6: Statistiques quotidiennes de traitement des factures';

-- ===========================================
-- 3. Fonctions utilitaires
-- ===========================================

-- Fonction pour incrémenter les stats (utilisée par n8n)
CREATE OR REPLACE FUNCTION increment_processing_stat(
    p_company_id UUID,
    p_stat_name TEXT,
    p_increment INTEGER DEFAULT 1
) RETURNS VOID AS $$
BEGIN
    INSERT INTO processing_stats (company_id, stat_date, invoices_processed)
    VALUES (p_company_id, CURRENT_DATE, 0)
    ON CONFLICT (company_id, stat_date) DO NOTHING;
    
    EXECUTE format(
        'UPDATE processing_stats SET %I = %I + $1, updated_at = NOW() 
         WHERE company_id = $2 AND stat_date = CURRENT_DATE',
        p_stat_name, p_stat_name
    ) USING p_increment, p_company_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION increment_processing_stat IS 'Incrémente un compteur de stats pour la date du jour';

-- ===========================================
-- 4. Vues pour monitoring
-- ===========================================

-- Vue des erreurs non résolues des dernières 24h
CREATE OR REPLACE VIEW v_recent_errors AS
SELECT 
    id,
    workflow_name,
    node_name,
    error_type,
    error_message,
    retry_count,
    created_at
FROM error_logs
WHERE created_at > NOW() - INTERVAL '24 hours'
  AND resolved = false
ORDER BY created_at DESC;

-- Vue des stats de la semaine
CREATE OR REPLACE VIEW v_weekly_stats AS
SELECT 
    c.name as company_name,
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
WHERE ps.stat_date > CURRENT_DATE - INTERVAL '7 days'
ORDER BY ps.stat_date DESC, c.name;

-- ===========================================
-- 5. Requêtes utiles pour n8n
-- ===========================================

-- Insérer une erreur (pour node PostgreSQL n8n)
/*
INSERT INTO error_logs (workflow_name, node_name, error_type, error_message, input_data, retry_count)
VALUES ($1, $2, $3, $4, $5::jsonb, $6)
RETURNING id;
*/

-- Incrémenter stats facture traitée avec succès
/*
INSERT INTO processing_stats (company_id, stat_date, invoices_processed, invoices_success, rag_hits)
VALUES ($1, CURRENT_DATE, 1, 1, 1)
ON CONFLICT (company_id, stat_date) 
DO UPDATE SET 
    invoices_processed = processing_stats.invoices_processed + 1,
    invoices_success = processing_stats.invoices_success + 1,
    rag_hits = processing_stats.rag_hits + 1,
    updated_at = NOW();
*/

-- Compter erreurs non résolues par type
/*
SELECT error_type, COUNT(*) as count
FROM error_logs
WHERE resolved = false
GROUP BY error_type
ORDER BY count DESC;
*/
