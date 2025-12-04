# Guide : Extension AL pour APIs Custom Business Central

Ce guide explique comment créer et déployer l'extension AL qui expose des champs non disponibles dans l'API standard de Business Central.

## Table des matières

1. [Contexte](#contexte)
2. [Prérequis](#prérequis)
3. [Création du projet AL](#création-du-projet-al)
4. [Configuration](#configuration)
5. [Téléchargement des symboles](#téléchargement-des-symboles)
6. [Création des APIs custom](#création-des-apis-custom)
7. [Compilation et publication](#compilation-et-publication)
8. [Test des APIs](#test-des-apis)
9. [Résolution des erreurs](#résolution-des-erreurs)
10. [Migration vers Production](#migration-vers-production)

## Contexte

### Le problème

L'API standard Business Central v2.0 ne permet pas de :
- Définir les **Posting Groups** (Gen. Bus., Vendor, VAT Bus.) lors de la création de vendors
- Accéder au champ **Payment Reference** sur les factures d'achat
- Définir les **Dimensions** (MANDAT, SOUS-MANDAT) sur les lignes de facture

### Conséquences

Sans ces champs :
```
Erreur : "Gen. Bus. Posting Group must have a value in Vendor: No.=V00010. 
         It cannot be zero or empty"
```

Les vendors créés via l'API ne peuvent pas être utilisés pour créer des factures, et les dimensions analytiques ne peuvent pas être assignées automatiquement.

### La solution

Créer une extension AL qui expose des APIs custom avec les champs manquants.

## Prérequis

### Logiciels requis

1. **Visual Studio Code**
   - Télécharger : https://code.visualstudio.com/

2. **Extension AL Language**
   - Ouvrir VS Code
   - `Ctrl+Shift+X` → Rechercher "AL Language"
   - Installer l'extension Microsoft

### Environnement Business Central

- Un environnement **Sandbox** est requis
- Le développement AL n'est **pas autorisé** en Production
- Accès administrateur au tenant

### Informations à collecter

| Information | Où la trouver |
|-------------|---------------|
| Tenant ID | Business Central Admin Center → Environments |
| Environment Name | Admin Center → nom exact de l'environnement |
| Company ID | API : `/companies` |

## Création du projet AL

### Étape 1 : Créer le projet

1. Ouvrir VS Code
2. `Ctrl+Shift+P` → `AL: Go!`
3. Sélectionner un dossier (ex: `C:\Users\[User]\Documents\AL\QRReaderAPI`)
4. Choisir la version Business Central correspondant à votre environnement
5. Sélectionner **"Microsoft cloud sandbox"**

### Étape 2 : Structure créée

```
QRReaderAPI/
├── .vscode/
│   └── launch.json
├── .alpackages/        (créé après téléchargement symboles)
├── app.json
└── HelloWorld.al       (à supprimer)
```

## Configuration

### app.json

Modifier le fichier `app.json` :

```json
{
  "id": "b4a5136c-97b6-47b0-b72b-333a64b8f37b",
  "name": "QR Reader Custom API",
  "publisher": "VotreNom",
  "version": "1.3.0.0",
  "brief": "Custom APIs for QR-bill automation",
  "description": "Extension exposant des APIs custom pour l'automatisation des QR-factures suisses",
  "application": "27.0.0.0",
  "idRanges": [
    {
      "from": 50100,
      "to": 50149
    }
  ],
  "runtime": "14.0",
  "target": "Cloud"
}
```

**Notes importantes :**
- `id` : Générez un GUID unique (ou gardez celui-ci)
- `application` : Doit correspondre à la version de votre BC (vérifiez dans Admin Center)
- `idRanges` : Plage d'IDs pour vos objets (50000-99999 pour les extensions)

### launch.json

Modifier `.vscode/launch.json` :

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Microsoft cloud sandbox",
      "type": "al",
      "request": "launch",
      "environmentType": "Sandbox",
      "environmentName": "Sandbox",
      "startupObjectId": 0,
      "startupObjectType": "None",
      "breakOnError": "All",
      "launchBrowser": true,
      "tenant": "VOTRE-TENANT-ID"
    }
  ]
}
```

**Important :** 
- `environmentName` doit correspondre **exactement** au nom dans Admin Center
- `tenant` est votre tenant ID Azure

## Téléchargement des symboles

Les symboles sont nécessaires pour que VS Code comprenne les tables et objets Business Central.

### Étapes

1. `Ctrl+Shift+P` → `AL: Download Symbols`
2. Authentifiez-vous avec votre compte Business Central
3. Attendez le message "All reference symbols have been downloaded"

### En cas d'erreur

| Erreur | Solution |
|--------|----------|
| "Not Found" | Vérifiez `environmentName` dans launch.json |
| "Unauthorized" | Vérifiez vos droits d'accès au tenant |
| "Internal Server Error" | Vous ciblez peut-être Production |

## Création des APIs custom

### Supprimer le fichier exemple

Supprimez `HelloWorld.al` (fichier exemple créé automatiquement).

### API Vendor (Page 50100)

Créer `CustomVendorAPI.al` - expose les posting groups pour créer des vendors valides.

### API Purchase Invoice (Page 50101)

Créer `CustomPurchaseInvoiceAPI.al` - expose le champ `paymentReference` pour les QR-factures.

### API Purchase Line (Page 50102)

Créer `CustomPurchaseLineAPI.al` - expose les dimensions pour assigner MANDAT et SOUS-MANDAT :

```al
page 50102 "Custom Purchase Line API"
{
    APIGroup = 'qrReader';
    APIPublisher = 'davidb';
    APIVersion = 'v1.0';
    EntityName = 'customPurchaseLine';
    EntitySetName = 'customPurchaseLines';
    PageType = API;
    SourceTable = "Purchase Line";
    SourceTableView = where("Document Type" = const(Invoice));
    DelayedInsert = true;
    ODataKeyFields = SystemId;
    Editable = true;

    layout
    {
        area(Content)
        {
            repeater(GroupName)
            {
                field(id; Rec.SystemId) { Editable = false; }
                field(documentNo; Rec."Document No.") { }
                field(type; Rec.Type) { }
                field(no; Rec."No.") { }
                field(description; Rec.Description) { }
                field(quantity; Rec.Quantity) { }
                field(directUnitCost; Rec."Direct Unit Cost") { }
                // Dimensions
                field(shortcutDimension1Code; Rec."Shortcut Dimension 1 Code") { }
                field(shortcutDimension2Code; Rec."Shortcut Dimension 2 Code") { }
            }
        }
    }
}
```

### API Dimension Set Entry (Page 50103)

Créer `CustomDimensionSetEntryAPI.al` - permet de lire les valeurs de dimensions.

Voir les fichiers complets dans le dossier `al-extension/`.

## Configuration des Dimensions

Avant d'utiliser les dimensions via l'API, configurez-les dans Business Central :

### General Ledger Setup → Dimensions

| Dimension | Code |
|-----------|------|
| Global Dimension 1 | MANDAT |
| Global Dimension 2 | SOUS-MANDAT |
| Shortcut Dimension 1 | MANDAT |
| Shortcut Dimension 2 | SOUS-MANDAT |

### Créer des valeurs de dimension

1. Recherche (Alt+Q) → "Dimension Values"
2. Filtre par Dimension Code = MANDAT
3. Créer les valeurs (ex: 752, 754, 764, etc.)

## Compilation et publication

### Compiler

1. `Ctrl+Shift+B` ou `AL: Build`
2. Vérifiez qu'il n'y a pas d'erreurs dans le panneau "Problems"

### Publier

1. `Ctrl+Shift+P` → `AL: Publish` (ou `F5`)
2. Authentifiez-vous si demandé
3. Attendez le message "Success: The package has been published"

## Test des APIs

### URL de base

```
https://api.businesscentral.dynamics.com/v2.0/{tenantId}/{environmentName}/api/davidb/qrReader/v1.0
```

### Créer une ligne de facture avec dimension

```http
POST .../companies({companyId})/customPurchaseLines
Content-Type: application/json

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

### Avec n8n

```json
{
  "documentNo": "{{ $('Create Purchase Invoice').item.json.number }}",
  "type": "G/L Account",
  "no": "6510",
  "description": "{{ $('Webhook').item.json.body.parsedData.companyName }}",
  "quantity": 1,
  "directUnitCost": {{ Number($('Webhook').item.json.body.parsedData.amount) || 0 }},
  "shortcutDimension1Code": "{{ $('Webhook').item.json.body.parsedData.mandat || '' }}",
  "shortcutDimension2Code": ""
}
```

## Résolution des erreurs

### Erreurs de compilation

| Erreur | Cause | Solution |
|--------|-------|----------|
| `Record X does not contain field Y` | Champ inexistant dans cette localisation | Supprimer le champ |
| `The name X does not exist` | Symboles non téléchargés | Télécharger les symboles |
| `ID X is already in use` | Conflit d'ID | Changer l'ID de l'objet |

### Erreurs de publication

| Erreur | Cause | Solution |
|--------|-------|----------|
| "Internal Server Error" | Publication en Production | Utiliser Sandbox |
| "Not Found" | Mauvais environmentName | Vérifier le nom exact |
| "Unauthorized" | Token expiré | Se réauthentifier |

### Erreurs d'exécution

| Erreur | Cause | Solution |
|--------|-------|----------|
| 404 sur l'API | API non publiée | Republier l'extension |
| Champ non trouvé | Version non à jour | Incrémenter version + republier |
| JSON invalid | Syntaxe JSON incorrecte | Vérifier les virgules et guillemets |

## Migration vers Production

Une fois les tests terminés sur Sandbox :

### Étape 1 : Modifier launch.json

```json
{
  "environmentType": "Production",
  "environmentName": "Production"
}
```

### Étape 2 : Incrémenter la version

Dans `app.json` :
```json
"version": "1.4.0.0"
```

### Étape 3 : Publier

`Ctrl+Shift+P` → `AL: Publish` pour publier en Production.

### Étape 4 : Mettre à jour les URLs

Remplacer `/Sandbox/` par `/Production/` dans toutes vos configurations n8n.

## Ressources

- [Documentation AL Language](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-reference-overview)
- [API Pages in AL](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-api-pagetype)
- [Business Central API v2.0](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/)
- [OData Query Options](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/webservices/use-odata-to-modify-data)
