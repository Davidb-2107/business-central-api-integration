# Roadmap : Automatisation des Factures Fournisseurs

> Document de référence pour les évolutions du système d'automatisation des factures QR suisses vers Business Central.
> 
> **Dernière mise à jour** : 11 Décembre 2025

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

## ✅ Phase 1 : COMPLÈTE ✅

> **Statut** : Pipeline end-to-end opérationnel - Testé avec succès le 11/12/2025

### Test de validation
| Élément | Résultat |
|---------|----------|
| Facture test | SERAFE AG - Redevance radio-TV |
| Vendor | ✅ Créé automatiquement dans BC |
| Montant | ✅ 335.00 CHF correct |
| Référence paiement | ✅ QR reference présente |
| Dimension MANDAT | ✅ Code 93622 appliqué |

### Architecture finale Phase 1

```
📱 QR-reader (Vercel)
      │
      ▼ POST /api/send-to-n8n
┌─────────────────────────────────────────────────────────┐
│  🔄 Workflow 1: EXTRACTION                              │
│                                                          │
│  Webhook → Tesseract OCR → Regex Patterns               │
│                 │                                        │
│                 ▼                                        │
│         needsLLM?                                        │
│         ├─ NO  → extractedFields (gratuit)              │
│         └─ YES → Infomaniak LLM (~0.002€)               │
│                 │                                        │
│                 ▼                                        │
│         Redis LPUSH (queue)                             │
└─────────────────────────────────────────────────────────┘
                  │
                  ▼
           📦 Redis Queue
           (invoice-extraction-queue)
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│  🔄 Workflow 2: BC CONNECTOR                            │
│                                                          │
│  Redis RPOP → Parse Redis Data                          │
│                 │                                        │
│                 ▼                                        │
│         Get OAuth Token                                  │
│                 │                                        │
│                 ▼                                        │
│         Search Vendor (by name)                         │
│         ├─ Found → Use existing                         │
│         └─ Not found → Create Vendor                    │
│                 │                                        │
│                 ▼                                        │
│         Create Purchase Invoice                         │
│                 │                                        │
│                 ▼                                        │
│         Create Purchase Line + Dimensions               │
└─────────────────────────────────────────────────────────┘
                  │
                  ▼
           ✅ Business Central
           (Facture brouillon créée)
```

### Composants opérationnels

| Composant | Statut | Description |
|-----------|--------|-------------|
| QR-reader | ✅ | App web Vercel, décode QR Swiss, envoie vers n8n |
| Tesseract OCR | ✅ | Container Docker VPS, API REST port 5000 |
| Regex extraction | ✅ | Patterns pour code_mandat, numero_facture, libelle |
| Infomaniak LLM | ✅ | Fallback si regex échoue (llama3, hébergé Suisse) |
| Redis Queue | ✅ | Découplage Extraction ↔ BC Connector |
| Workflow Extraction | ✅ | OCR + extraction + push Redis |
| Workflow BC Connector | ✅ | Pop Redis + OAuth + Vendor + Invoice + Dimensions |
| AL Extension BC | ✅ | APIs custom (Vendor, PurchaseInvoice, PurchaseLine, Dimensions) |

### Chemins JSON - Référence

**Workflow 1 (Extraction) - Après Webhook:**
```javascript
$json.body.parsedData.companyName     // "SERAFE AG"
$json.body.parsedData.vendorName      // "SERAFE AG"
$json.body.parsedData.amount          // "335.00"
$json.body.parsedData.reference       // "278600317270190039362280099"
$json.body.parsedData.iban            // "CH893000520211491010B"
```

**Workflow 2 (BC Connector) - Après Parse Redis Data:**
```javascript
$json.parsedData.companyName          // "SERAFE AG"
$json.parsedData.vendorName           // "SERAFE AG"
$json.parsedData.vendorAddress        // "Summelenweg, 91, 8808 Pfäffikon SZ, CH"
$json.parsedData.amount               // "335.00"
$json.parsedData.reference            // "278600317270190039362280099"
$json.extractedFields.code_mandat     // "93622"
$json.extractedFields.numero_facture  // "RF-0393-6228-009"
$json.extractedFields.libelle         // "Redevance de radio-télévision"
```

### Structure données Redis

```json
{
  "propertyName": {
    "ocrText": "... texte OCR complet ...",
    "parsedData": {
      "companyName": "SERAFE AG",
      "vendorName": "SERAFE AG",
      "vendorAddress": "Summelenweg, 91, 8808 Pfäffikon SZ, CH",
      "iban": "CH893000520211491010B",
      "amount": "335.00",
      "currency": "CHF",
      "reference": "278600317270190039362280099",
      "referenceType": "QRR"
    },
    "extractedFields": {
      "code_mandat": "93622",
      "numero_facture": "RF-0393-6228-009",
      "libelle": "Redevance de radio-télévision"
    },
    "source": "llm"
  }
}
```

> **Note**: Le node "Parse Redis Data" extrait `propertyName` pour simplifier les chemins downstream.

---

## 🚧 Phase 2 : RAG Auto-alimenté

### Concept
Base de connaissances qui apprend des factures validées pour suggérer le bon code mandat.

### Problème à résoudre
Le `code_mandat` extrait par OCR (ex: `602.201`) n'est PAS toujours le code mandat BC (ex: `754`).
Il faut un mapping intelligent basé sur :
- `vendorName` (Fonds de surcompensation)
- `debtorName` (Caisse Intercorporative vaudoise)
- `client_numero` (602.201)
- `company_id` (multi-société)

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

### Tâches Phase 2

- [ ] Créer table SQLite/D1 pour RAG
- [ ] Endpoint n8n pour alimenter RAG
- [ ] Modifier workflow : lookup RAG avant LLM
- [ ] Ajouter `mandat_suggere` + `confidence` dans réponse
- [ ] Implémenter feedback loop (polling ou webhook BC)
- [ ] Interface minimale pour correction manuelle (optionnel)

---

## 🔮 Phase 3 : Full Automation

### Triggers automatiques

| Source | Implémentation | Priorité |
|--------|----------------|----------|
| 📁 Dossier réseau | n8n Watch Folder node | Haute |
| 📧 Email | n8n IMAP/Gmail trigger | Moyenne |
| ☁️ SharePoint/OneDrive | n8n Microsoft trigger | Moyenne |
| 🔗 API directe | Webhook existant | ✅ Déjà fait |

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
| Tesseract OCR | http://tesseract-ocr:5000 (interne Docker) | OCR local |
| Redis | redis:6379 (interne Docker) | Queue entre workflows |
| Infomaniak AI | Product ID: 106537, Model: llama3 | LLM fallback RGPD |
| Business Central | OAuth2 Azure AD, Tenant: 5f225b4a-2f9e-4ba9-8863-ec7e18049f48 | API factures |

### Configuration Infomaniak AI

```
Endpoint: https://api.infomaniak.com/2/ai/106537/openai/v1/chat/completions
Model: llama3 (ou mistral3)
Auth: Bearer token
```

### Dimensions BC

| Dimension | Code | Usage |
|-----------|------|-------|
| MANDAT | Global Dim 1 | Code mandat (ex: 93622) |
| SOUS-MANDAT | Global Dim 2 | Sous-catégorie |

---

## 📝 Décisions techniques

### Pourquoi OCR local + LLM cloud ?

| Option testée | Résultat |
|---------------|----------|
| Ollama Vision (llama3.2-vision) | ❌ Trop lent sur CPU (3+ min/image) |
| Tesseract + Regex | ✅ Rapide (2-5s), gratuit, 80% des cas |
| Tesseract + LLM Infomaniak | ✅ Fallback intelligent, RGPD compliant |

### Pourquoi Redis Queue entre workflows ?

| Avantage | Description |
|----------|-------------|
| Découplage | Extraction et BC Connector indépendants |
| Scalabilité | Batch processing possible (100 factures en 1-2 min) |
| Résilience | Si BC down, factures en queue |
| Multi-ERP | Même extraction, connecteurs différents |

### Pourquoi RAG plutôt que rules engine ?

- Le mapping numéro client → mandat BC est imprévisible
- Varie par société
- Auto-apprentissage plus maintenable que règles manuelles

---

## 🎯 Prochaines actions

### ✅ Complété
- [x] Architecture 2 workflows avec Redis Queue
- [x] Pipeline end-to-end fonctionnel
- [x] Test SERAFE AG : vendor créé, facture avec dimensions

### Court terme (Phase 2)
- [ ] Créer structure RAG (SQLite)
- [ ] Implémenter lookup RAG dans workflow
- [ ] Ajouter feedback loop

### Moyen terme (Phase 3)
- [ ] Trigger dossier automatique
- [ ] Gestion multi-société automatique
- [ ] Monitoring et alertes

---

## 📞 Contexte pour nouvelles conversations

Pour reprendre ce projet dans une nouvelle conversation Claude, mentionner :

> "Je travaille sur l'automatisation des factures QR suisses vers Business Central. 
> Voir le document ROADMAP_INVOICE_AUTOMATION.md dans le repo business-central-api-integration.
> Phase actuelle : 1 COMPLÈTE, prêt pour Phase 2 RAG
> Prochaine tâche : [description]"

Claude aura accès au repo via MCP GitHub et pourra lire ce document pour comprendre le contexte complet.
