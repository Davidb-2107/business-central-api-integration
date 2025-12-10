# Roadmap : Automatisation des Factures Fournisseurs

> Document de référence pour les évolutions du système d'automatisation des factures QR suisses vers Business Central.
> 
> **Dernière mise à jour** : Décembre 2025

---

## 📋 Contexte

### Objectif final
Automatisation complète du traitement des factures fournisseurs :
1. Réception automatique (dossier, email, API)
2. Extraction des données (QR + OCR)
3. Détermination intelligente du code mandat
4. Création de facture brouillon dans Business Central
5. Validation humaine dans BC uniquement

### Contraintes
- **Multi-société** : Plusieurs sociétés BC avec des codes mandat différents
- **RGPD/LPD** : Données professionnelles en Europe uniquement
- **Mapping complexe** : Le numéro client sur facture ≠ code mandat BC
  - Exemple : `Client N° 602.201` sur facture → Mandat `754` dans BC

---

## ✅ État actuel (Phase 1)

### Composants opérationnels

| Composant | Statut | Description |
|-----------|--------|-------------|
| QR-reader | ✅ | App web Vercel, décode QR Swiss, capture canvas base64 |
| Tesseract OCR | ✅ | Container Docker VPS, API REST |
| Regex extraction | ✅ | Patterns pour code_mandat, numero_facture, libelle |
| Infomaniak LLM | ✅ | Fallback si regex échoue (llama3, Suisse) |
| Workflow n8n OCR | ✅ | Webhook → OCR → Regex → IF → LLM → Response |
| Workflow n8n BC | ✅ | OAuth → Check Vendor → Create Invoice |
| AL Extension BC | ✅ | APIs custom (Vendor, PurchaseInvoice, PurchaseLine, Dimensions) |

### Architecture actuelle

```
QR-reader (Vercel)
      │
      ▼ POST base64 + parsedData
n8n Workflow OCR
      │
      ├─► Tesseract OCR (2-5s)
      │
      ├─► Regex extraction
      │
      └─► IF needsLLM?
          ├─ false → extractedFields (gratuit)
          └─ true  → Infomaniak LLM (~0.002€)
      │
      ▼
Respond to Webhook
      │
      ▼ (Manuel actuellement)
n8n Workflow BC
      │
      ├─► OAuth Token
      ├─► Check/Create Vendor
      ├─► Create Purchase Invoice
      └─► Add Purchase Line + Dimensions
```

### Données extraites

| Source | Champs |
|--------|--------|
| **QR Code** | vendorName, IBAN, amount, reference, vendorAddress, debtorName |
| **OCR** | code_mandat (numéro client), numero_facture, libelle |

### Problème non résolu
Le `code_mandat` extrait par OCR (ex: `602.201`) n'est PAS le code mandat BC (ex: `754`).
Il faut un mapping intelligent basé sur :
- `vendorName` (Fonds de surcompensation)
- `debtorName` (Caisse Intercorporative vaudoise)
- `client_numero` (602.201)
- `company_id` (multi-société)

---

## 🚧 Phase 2 : RAG Auto-alimenté

### Concept
Base de connaissances qui apprend des factures validées pour suggérer le bon code mandat.

### Structure de données RAG

```json
{
  "id": "uuid",
  "company_id": "d0854afd-fdb9-...",
  "company_name": "CIVAF",
  "vendor_name": "Fonds de surcompensation",
  "debtor_name": "Caisse Intercorporative vaudoise",
  "client_numero": "602.201",
  "libelle_pattern": "Cotisation FONPRO",
  "mandat_bc": "754",
  "confidence": 0.95,
  "last_used": "2025-12-09",
  "usage_count": 12,
  "created_at": "2025-01-15"
}
```

### Flow avec RAG

```
Nouvelle facture
      │
      ▼
OCR + QR extraction
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ Recherche RAG                                           │
│ WHERE company_id = X                                    │
│   AND (vendor_name = Y OR debtor_name = Z               │
│        OR client_numero = W)                            │
└─────────────────────────────────────────────────────────┘
      │
      ▼
   Trouvé ?
   ├─ OUI (confiance > 80%) → Utiliser mandat_bc
   ├─ OUI (confiance < 80%) → Suggérer + flag review
   └─ NON → LLM avec contexte / flag review obligatoire
      │
      ▼
Créer facture BC (draft)
avec mandat suggéré
      │
      ▼
Validation humaine dans BC
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ Feedback loop                                           │
│ - Mandat confirmé → UPDATE confidence, usage_count      │
│ - Mandat corrigé → INSERT/UPDATE avec bonne valeur      │
└─────────────────────────────────────────────────────────┘
```

### Options stockage RAG

| Option | Avantages | Recommandation |
|--------|-----------|----------------|
| SQLite | Simple, requêtes SQL, fichier local | ⭐ Phase 2 |
| D1 Cloudflare | Hébergé, SQL, gratuit | Alternative |
| PostgreSQL | Robuste, scalable | Phase 3+ |

### Feedback loop depuis BC

**Option A** : Webhook BC (si disponible via AL extension)
```
Facture postée → Trigger AL → HTTP Request → n8n → Update RAG
```

**Option B** : Polling n8n (plus simple)
```
Cron n8n (toutes les heures)
  → GET factures postées dernière heure
  → Comparer draft vs final
  → Update RAG
```

### Tâches Phase 2

- [ ] Créer table SQLite/D1 pour RAG
- [ ] Endpoint n8n pour alimenter RAG
- [ ] Modifier workflow : lookup RAG avant LLM
- [ ] Ajouter `mandat_suggere` + `confidence` dans réponse
- [ ] Implémenter feedback loop (polling ou webhook)
- [ ] Interface minimale pour correction manuelle (optionnel)

---

## 🔮 Phase 3 : Full Automation

### Triggers automatiques

| Source | Implémentation | Priorité |
|--------|----------------|----------|
| 📁 Dossier réseau | n8n Watch Folder node | Haute |
| 📧 Email | n8n IMAP/Gmail trigger | Moyenne |
| ☁️ SharePoint/OneDrive | n8n Microsoft trigger | Moyenne |
| 🔗 API directe | Webhook existant | Déjà fait |

### Architecture cible

```
┌─────────────────────────────────────────────────────────────────┐
│                    SOURCES D'ENTRÉE                             │
│  📁 Dossier    📧 Email    ☁️ SharePoint    📱 QR-reader        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    n8n ORCHESTRATOR                             │
│                                                                  │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────┐ │
│  │ PDF      │──▶│ OCR      │──▶│ RAG      │──▶│ Business     │ │
│  │ Extract  │   │ Tesseract│   │ Lookup   │   │ Central API  │ │
│  └──────────┘   └──────────┘   └──────────┘   └──────────────┘ │
│                                      │                          │
│                                      ▼                          │
│                              ┌──────────────┐                   │
│                              │ RAG Database │                   │
│                              │ (SQLite/D1)  │                   │
│                              └──────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 BUSINESS CENTRAL                                │
│  Facture brouillon → Validation humaine → Posting              │
│                              │                                   │
│                              ▼                                   │
│                    Feedback → RAG Update                        │
└─────────────────────────────────────────────────────────────────┘
```

### Tâches Phase 3

- [ ] Configurer trigger dossier (Watch Folder)
- [ ] Extraction PDF → images (pdf-poppler ou similaire)
- [ ] Détection automatique société BC (basée sur debtorName ?)
- [ ] Gestion des erreurs et alertes
- [ ] Dashboard de suivi (optionnel)
- [ ] QR-reader devient outil de debug/override

---

## 🔧 Ressources techniques

### Repositories

| Repo | Contenu |
|------|---------|
| [VPS_Infrastructure](https://github.com/Davidb-2107/VPS_Infrastructure) | Infra Docker, workflows n8n, services |
| [business-central-api-integration](https://github.com/Davidb-2107/business-central-api-integration) | AL Extension, guides API BC |
| [QR-reader](https://github.com/Davidb-2107/QR-reader) | App web scan QR Swiss |

### Services

| Service | URL/Accès | Usage |
|---------|-----------|-------|
| n8n | https://n8n.hen8n.com | Orchestration workflows |
| Tesseract OCR | http://tesseract-ocr:5000 (interne) | OCR local |
| Infomaniak AI | Product ID: 106537, Model: llama3 | LLM fallback |
| Business Central | OAuth2 Azure AD | API factures |

### Configuration Infomaniak AI

```
Endpoint: https://api.infomaniak.com/2/ai/106537/openai/v1/chat/completions
Model: llama3 (ou mistral3)
Auth: Bearer token
```

### Dimensions BC

| Dimension | Code | Usage |
|-----------|------|-------|
| MANDAT | Global Dim 1 | Code mandat (ex: 754) |
| SOUS-MANDAT | Global Dim 2 | Sous-catégorie |

---

## 📝 Décisions techniques

### Pourquoi OCR local + LLM cloud ?

| Option testée | Résultat |
|---------------|----------|
| Ollama Vision (llama3.2-vision) | ❌ Trop lent sur CPU (3+ min/image) |
| Tesseract + Regex | ✅ Rapide (2-5s), gratuit, 80% des cas |
| Tesseract + LLM Infomaniak | ✅ Fallback intelligent, RGPD compliant |

### Pourquoi pas PDF base64 vers LLM ?

- Vision models trop lents sur CPU
- OCR + texte suffit pour extraction
- PDF conservé pour archivage, pas pour IA

### Pourquoi RAG plutôt que rules engine ?

- Le mapping numéro client → mandat BC est imprévisible
- Varie par société
- Auto-apprentissage plus maintenable que règles manuelles

---

## 🎯 Prochaines actions

### Immédiat
1. [ ] Fusionner workflow OCR + workflow BC en un seul
2. [ ] Tester end-to-end avec vraie facture

### Court terme (Phase 2)
3. [ ] Créer structure RAG (SQLite)
4. [ ] Implémenter lookup RAG dans workflow
5. [ ] Ajouter feedback loop

### Moyen terme (Phase 3)
6. [ ] Trigger dossier automatique
7. [ ] Gestion multi-société automatique
8. [ ] Monitoring et alertes

---

## 📞 Contexte pour nouvelles conversations

Pour reprendre ce projet dans une nouvelle conversation Claude, mentionner :

> "Je travaille sur l'automatisation des factures QR suisses vers Business Central. 
> Voir le document ROADMAP_INVOICE_AUTOMATION.md dans le repo business-central-api-integration.
> Phase actuelle : [1/2/3]
> Prochaine tâche : [description]"

Claude aura accès au repo via MCP GitHub et pourra lire ce document pour comprendre le contexte complet.
