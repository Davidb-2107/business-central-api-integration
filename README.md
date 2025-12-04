# 🚀 Business Central API Integration

Guide complet pour intégrer Microsoft Dynamics 365 Business Central avec des outils d'automatisation via OAuth 2.0.

## 📖 À propos

Ce repository contient la documentation complète pour configurer l'accès aux APIs de Business Central Online en utilisant l'authentification OAuth 2.0 (Service-to-Service). Cette configuration permet l'automatisation et l'intégration avec des outils comme n8n, Power Automate, Zapier, et plus encore.

## 📚 Documentation

### [📘 Guide de Configuration API](./GUIDE_CONFIGURATION_API.md)

Configuration de l'authentification OAuth 2.0 :
- ✅ Configuration du tenant Microsoft 365
- 🔐 Création de l'App Registration dans Azure
- 🔑 Configuration des permissions OAuth 2.0
- 🧪 Tests avec Postman
- 🔌 Intégration avec n8n
- ❌ Résolution des erreurs courantes

### [📗 Guide Extension AL](./GUIDE_AL_EXTENSION.md)

Création d'APIs custom pour les champs non exposés :
- 🔧 Création de projet AL dans VS Code
- 📦 Extension pour Vendors (avec Posting Groups)
- 📦 Extension pour Purchase Invoices (avec Payment Reference)
- 📦 Extension pour Purchase Lines (avec Dimensions)
- 🚀 Compilation et déploiement

### [📁 Extension AL](./al-extension/)

Code source de l'extension AL v1.3.0 :
- `CustomVendorAPI.al` - API custom pour les vendors
- `CustomPurchaseInvoiceAPI.al` - API custom pour les factures d'achat
- `CustomPurchaseLineAPI.al` - API custom pour les lignes avec dimensions
- `CustomDimensionSetEntryAPI.al` - API pour lire les valeurs de dimensions

### [📄 Spécification QR-Reader](./docs/QR_READER_MANDAT_SPEC.md)

Spécification pour l'ajout du champ Mandat dans l'application QR-Reader.

## 🎯 Cas d'Usage

Ce repository vous permet de :
- **Automatiser les QR-factures suisses** : Scanner → Extraire → Créer facture dans BC
- Synchroniser Business Central avec votre CRM
- Automatiser la création de factures avec les bons posting groups
- Enregistrer la référence de paiement QR sur les factures
- **Assigner automatiquement les dimensions analytiques (MANDAT)**
- Exporter des données vers Excel/Google Sheets
- Créer des notifications automatiques (Slack, Email)

## 🏗️ Architecture complète

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  QR-Reader  │────▶│    n8n      │────▶│ Custom API  │────▶│  Business   │
│  (PDF scan) │     │  Workflow   │     │ (AL ext.)   │     │  Central    │
│  + Mandat   │     │             │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ├──▶ Search/Create Vendor (posting groups)
                           ├──▶ Create Invoice (paymentReference)
                           └──▶ Create Invoice Line (dimensions MANDAT)
```

## ⚡ Démarrage Rapide

1. Créez un tenant Microsoft 365 Business
2. Ajoutez Business Central Online (essai 30 jours)
3. Suivez le [guide de configuration OAuth](./GUIDE_CONFIGURATION_API.md)
4. Déployez l'[extension AL](./al-extension/) pour les APIs custom
5. Configurez les dimensions (MANDAT, SOUS-MANDAT) dans General Ledger Setup
6. Testez avec Postman
7. Commencez vos automatisations !

## 🛠️ Technologies

- Microsoft Dynamics 365 Business Central Online
- OAuth 2.0 (Client Credentials Flow)
- Microsoft Entra ID (Azure AD)
- AL Language (Visual Studio Code)
- Postman (tests)
- n8n (automatisation)
- Vercel (hébergement QR-Reader)

## 📋 Prérequis

- Compte Microsoft 365 Business (~5,60€/mois)
- Environnement Business Central Online (Sandbox pour le développement)
- Accès administrateur Azure Portal
- Visual Studio Code + Extension AL Language
- Postman (gratuit)

## 📦 APIs Custom exposées (v1.3.0)

| Page ID | Endpoint | Description | Champs clés |
|---------|----------|-------------|-------------|
| 50100 | `/customVendors` | Vendors | genBusPostingGroup, vendorPostingGroup, vatBusPostingGroup |
| 50101 | `/customPurchaseInvoices` | Factures | paymentReference |
| 50102 | `/customPurchaseLines` | Lignes facture | shortcutDimension1Code (MANDAT), shortcutDimension2Code |
| 50103 | `/dimensionSetEntries` | Dimensions | dimensionCode, dimensionValueCode |

Base URL : `https://api.businesscentral.dynamics.com/v2.0/{tenantId}/{environment}/api/davidb/qrReader/v1.0`

## 🔧 Configuration des Dimensions

Dans **General Ledger Setup** → **Dimensions** :

| Dimension | Code |
|-----------|------|
| Global Dimension 1 | MANDAT |
| Global Dimension 2 | SOUS-MANDAT |
| Shortcut Dimension 1 | MANDAT |
| Shortcut Dimension 2 | SOUS-MANDAT |

## 📝 Exemple de workflow n8n

### Body pour créer une ligne de facture avec dimension

```json
{
  "documentNo": "107218",
  "type": "G/L Account",
  "no": "6510",
  "description": "CENTRE PATRONAL",
  "quantity": 1,
  "directUnitCost": 18250.00,
  "shortcutDimension1Code": "764",
  "shortcutDimension2Code": ""
}
```

## 🔗 Ressources Utiles

### Documentation Microsoft
- [OAuth pour Business Central](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/webservices/authenticate-web-services-using-oauth)
- [Service-to-Service Authentication](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/automation-apis-using-s2s-authentication)
- [Business Central API Reference](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/)
- [AL Language Documentation](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-reference-overview)

### Outils
- [Postman](https://www.postman.com/)
- [n8n](https://n8n.io/)
- [Azure Portal](https://portal.azure.com)
- [Visual Studio Code](https://code.visualstudio.com/)

## ⚠️ Notes Importantes

- 🔐 Ne jamais committer les secrets dans Git
- 🔄 Les tokens expirent après 1 heure (renouvellement automatique)
- ⚡ Respectez les limites d'appels API de Microsoft
- 📊 Basic Auth est déprécié depuis 2022
- 🧪 Le développement AL n'est autorisé que sur les environnements Sandbox

## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à :
- Ouvrir une Issue pour signaler un problème
- Proposer des améliorations via Pull Request
- Partager vos cas d'usage

## 📄 Licence

Ce guide est fourni à titre informatif. Microsoft, Dynamics 365 et Business Central sont des marques déposées de Microsoft Corporation.

## 👤 Auteur

**David B.**
- GitHub: [@Davidb-2107](https://github.com/Davidb-2107)

---

**⭐ Si ce guide vous a été utile, n'hésitez pas à lui donner une étoile !**
