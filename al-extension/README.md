# QR Reader Custom API - AL Extension

Extension AL pour Business Central exposant des APIs custom nécessaires à l'automatisation des QR-factures suisses.

## Pourquoi cette extension ?

L'API standard Business Central v2.0 ne permet pas de :
- Définir les **Posting Groups** (Gen. Bus., Vendor, VAT Bus.) lors de la création de vendors
- Accéder au champ **Payment Reference** sur les factures d'achat
- Définir les **Dimensions** (MANDAT, SOUS-MANDAT) sur les lignes de facture

Sans ces champs :
- Les vendors créés génèrent une erreur lors de la création de factures
- La référence QR suisse ne peut pas être enregistrée sur les factures
- Les dimensions analytiques ne peuvent pas être assignées automatiquement

## APIs exposées

| Page ID | Endpoint | Description |
|---------|----------|-------------|
| 50100 | `/api/davidb/qrReader/v1.0/customVendors` | Vendors avec posting groups |
| 50101 | `/api/davidb/qrReader/v1.0/customPurchaseInvoices` | Factures avec payment reference |
| 50102 | `/api/davidb/qrReader/v1.0/customPurchaseLines` | Lignes de facture avec dimensions |
| 50103 | `/api/davidb/qrReader/v1.0/dimensionSetEntries` | Lecture des valeurs de dimensions |

## Configuration des dimensions

Dans **General Ledger Setup** → **Dimensions** :

| Dimension | Code |
|-----------|------|
| Global Dimension 1 | MANDAT |
| Global Dimension 2 | SOUS-MANDAT |
| Shortcut Dimension 1 | MANDAT |
| Shortcut Dimension 2 | SOUS-MANDAT |

## Installation

### Prérequis

- Visual Studio Code
- Extension AL Language (Microsoft)
- Business Central Sandbox environment

### Étapes

1. Ouvrir ce dossier dans VS Code
2. Modifier `.vscode/launch.json` avec votre tenant ID
3. `Ctrl+Shift+P` → `AL: Download Symbols`
4. `Ctrl+Shift+B` pour compiler
5. `Ctrl+Shift+P` → `AL: Publish` pour publier sur le Sandbox

## Utilisation

### URL de base

```
https://api.businesscentral.dynamics.com/v2.0/{tenantId}/Sandbox/api/davidb/qrReader/v1.0
```

### Créer un vendor avec posting groups

```http
POST /companies({companyId})/customVendors
Content-Type: application/json

{
  "displayName": "Mon Fournisseur SA",
  "addressLine1": "Rue Example 1",
  "city": "Lausanne",
  "postalCode": "1000",
  "country": "CH",
  "genBusPostingGroup": "INLAND",
  "vendorPostingGroup": "INLAND",
  "vatBusPostingGroup": "INLAND"
}
```

### Créer une facture avec payment reference

```http
POST /companies({companyId})/customPurchaseInvoices
Content-Type: application/json

{
  "vendorNumber": "V00001",
  "invoiceDate": "2025-12-03",
  "vendorInvoiceNumber": "INV-2025-001",
  "paymentReference": "000000000000002250627109240"
}
```

### Créer une ligne de facture avec dimensions

```http
POST /companies({companyId})/customPurchaseLines
Content-Type: application/json

{
  "documentNo": "107218",
  "type": "G/L Account",
  "no": "6510",
  "description": "Prestation de service",
  "quantity": 1,
  "directUnitCost": 18250.00,
  "shortcutDimension1Code": "764",
  "shortcutDimension2Code": ""
}
```

### Lire les dimensions d'un Dimension Set

```http
GET /companies({companyId})/dimensionSetEntries?$filter=dimensionSetId eq 4
```

## Champs exposés

### customVendor

| Champ | Description | Éditable |
|-------|-------------|----------|
| id | SystemId | Non |
| number | No. | Oui |
| displayName | Name | Oui |
| addressLine1 | Address | Oui |
| addressLine2 | Address 2 | Oui |
| city | City | Oui |
| postalCode | Post Code | Oui |
| country | Country/Region Code | Oui |
| phoneNumber | Phone No. | Oui |
| email | E-Mail | Oui |
| **genBusPostingGroup** | Gen. Bus. Posting Group | Oui |
| **vendorPostingGroup** | Vendor Posting Group | Oui |
| **vatBusPostingGroup** | VAT Bus. Posting Group | Oui |
| paymentTermsCode | Payment Terms Code | Oui |
| currencyCode | Currency Code | Oui |
| blocked | Blocked | Oui |
| balance | Balance | Non |
| lastModifiedDateTime | SystemModifiedAt | Non |

### customPurchaseInvoice

| Champ | Description | Éditable |
|-------|-------------|----------|
| id | SystemId | Non |
| number | No. | Oui |
| vendorNumber | Buy-from Vendor No. | Oui |
| vendorName | Buy-from Vendor Name | Non |
| postingDate | Posting Date | Oui |
| invoiceDate | Document Date | Oui |
| dueDate | Due Date | Oui |
| vendorInvoiceNumber | Vendor Invoice No. | Oui |
| **paymentReference** | Payment Reference | Oui |
| currencyCode | Currency Code | Oui |
| status | Status | Non |
| lastModifiedDateTime | SystemModifiedAt | Non |

### customPurchaseLine

| Champ | Description | Éditable |
|-------|-------------|----------|
| id | SystemId | Non |
| documentNo | Document No. | Oui |
| lineNo | Line No. | Non |
| type | Type (G/L Account, Item, etc.) | Oui |
| no | No. (compte ou article) | Oui |
| description | Description | Oui |
| quantity | Quantity | Oui |
| directUnitCost | Direct Unit Cost | Oui |
| lineAmount | Line Amount | Non |
| amount | Amount | Non |
| amountIncludingVAT | Amount Including VAT | Non |
| **shortcutDimension1Code** | MANDAT | Oui |
| **shortcutDimension2Code** | SOUS-MANDAT | Oui |
| dimensionSetID | Dimension Set ID | Non |

### dimensionSetEntry

| Champ | Description | Éditable |
|-------|-------------|----------|
| dimensionSetId | Dimension Set ID | Non |
| dimensionCode | Dimension Code | Non |
| dimensionValueCode | Dimension Value Code | Non |
| dimensionValueName | Dimension Value Name | Non |

## Intégration avec n8n

### Configuration

Dans le nœud Config de votre workflow n8n :

```json
{
  "apiBaseUrl": "https://api.businesscentral.dynamics.com/v2.0/{tenantId}/Sandbox/api/v2.0",
  "customApiBaseUrl": "https://api.businesscentral.dynamics.com/v2.0/{tenantId}/Sandbox/api/davidb/qrReader/v1.0",
  "companyId": "votre-company-id"
}
```

### Workflow complet

```
[Webhook QR-Reader]
        │
        ▼
[Search Vendor] ──────── /customVendors?$filter=displayName eq 'xxx'
        │
        ▼
[Create Vendor?] ─────── /customVendors (avec posting groups)
        │
        ▼
[Create Invoice] ─────── /customPurchaseInvoices (avec paymentReference)
        │
        ▼
[Add Invoice Line] ───── /customPurchaseLines (avec dimensions MANDAT)
```

## Intégration avec QR-Reader

L'application QR-Reader doit envoyer les données suivantes au webhook n8n :

```json
{
  "parsedData": {
    "companyName": "CENTRE PATRONAL",
    "street": "Route du Lac",
    "buildingNumber": "2",
    "postalCode": "1094",
    "city": "Paudex",
    "country": "CH",
    "amount": 18250.00,
    "currency": "CHF",
    "reference": "22506271",
    "payment_reference": "000000000000002250627109240",
    "mandat": "764"
  }
}
```

Le champ `mandat` est optionnel et correspond au code Client N° visible sur certaines factures fournisseurs.

## Notes importantes

- Le développement AL n'est autorisé que sur les environnements **Sandbox**
- Pour déployer en Production, modifier `launch.json` et incrémenter la version
- Les posting groups "INLAND" sont appropriés pour les vendors suisses B2B
- Les codes MANDAT correspondent aux numéros de client chez les fournisseurs (ex: 764 pour CENTRE PATRONAL)
