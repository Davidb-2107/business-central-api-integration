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

### Conséquences

Sans ces champs :
```
Erreur : "Gen. Bus. Posting Group must have a value in Vendor: No.=V00010. 
         It cannot be zero or empty"
```

Les vendors créés via l'API ne peuvent pas être utilisés pour créer des factures.

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
  "version": "1.0.0.0",
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

Créer `CustomVendorAPI.al` :

```al
page 50100 "Custom Vendor API"
{
    APIGroup = 'qrReader';
    APIPublisher = 'davidb';
    APIVersion = 'v1.0';
    EntityName = 'customVendor';
    EntitySetName = 'customVendors';
    PageType = API;
    SourceTable = Vendor;
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(GroupName)
            {
                // Champs standards
                field(id; Rec.SystemId) { Editable = false; }
                field(number; Rec."No.") { }
                field(displayName; Rec.Name) { }
                // ... autres champs ...
                
                // Posting Groups (non disponibles dans l'API standard)
                field(genBusPostingGroup; Rec."Gen. Bus. Posting Group") { }
                field(vendorPostingGroup; Rec."Vendor Posting Group") { }
                field(vatBusPostingGroup; Rec."VAT Bus. Posting Group") { }
            }
        }
    }
}
```

### API Purchase Invoice (Page 50101)

Créer `CustomPurchaseInvoiceAPI.al` :

```al
page 50101 "Custom Purchase Invoice API"
{
    APIGroup = 'qrReader';
    APIPublisher = 'davidb';
    APIVersion = 'v1.0';
    EntityName = 'customPurchaseInvoice';
    EntitySetName = 'customPurchaseInvoices';
    PageType = API;
    SourceTable = "Purchase Header";
    SourceTableView = where("Document Type" = const(Invoice));
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(GroupName)
            {
                // Champs standards
                field(id; Rec.SystemId) { Editable = false; }
                field(vendorNumber; Rec."Buy-from Vendor No.") { }
                // ... autres champs ...
                
                // Payment Reference (non disponible dans l'API standard)
                field(paymentReference; Rec."Payment Reference") { }
            }
        }
    }
}
```

Voir les fichiers complets dans le dossier `al-extension/`.

## Compilation et publication

### Compiler

1. `Ctrl+Shift+B` ou `AL: Build`
2. Vérifiez qu'il n'y a pas d'erreurs dans le panneau "Problems"

### Publier

1. `F5` ou `AL: Publish`
2. Authentifiez-vous si demandé
3. Attendez le message "Success: The package has been published"

## Test des APIs

### URL de base

```
https://api.businesscentral.dynamics.com/v2.0/{tenantId}/{environmentName}/api/davidb/qrReader/v1.0
```

### Avec Postman

**GET - Lister les vendors :**
```
GET .../companies({companyId})/customVendors
Authorization: Bearer {token}
```

**POST - Créer un vendor :**
```json
POST .../companies({companyId})/customVendors
Content-Type: application/json

{
  "displayName": "Test Vendor",
  "genBusPostingGroup": "INLAND",
  "vendorPostingGroup": "INLAND",
  "vatBusPostingGroup": "INLAND"
}
```

### Avec n8n

Utilisez un nœud HTTP Request avec :
- Method: GET ou POST
- URL: L'URL de l'API custom
- Authentication: OAuth2 (configuré pour Business Central)

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
"version": "1.1.0.0"
```

### Étape 3 : Publier

`F5` pour publier en Production.

### Étape 4 : Mettre à jour les URLs

Remplacer `/Sandbox/` par `/Production/` dans toutes vos configurations n8n.

## Ressources

- [Documentation AL Language](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-reference-overview)
- [API Pages in AL](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-api-pagetype)
- [Business Central API v2.0](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/)
- [OData Query Options](https://docs.microsoft.com/en-us/dynamics365/business-central/dev-itpro/webservices/use-odata-to-modify-data)
