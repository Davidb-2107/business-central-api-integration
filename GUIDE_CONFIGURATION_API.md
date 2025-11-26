# Guide de Configuration API Business Central avec OAuth 2.0

## 📋 Vue d'ensemble

Ce guide documente les étapes pour configurer l'accès aux APIs de Microsoft Dynamics 365 Business Central Online en utilisant l'authentification OAuth 2.0 (Service-to-Service).

**Objectif** : Permettre l'automatisation et l'intégration de Business Central avec des outils externes (n8n, Power Automate, etc.)

---

## ✅ Prérequis

- Un compte Microsoft 365 Business (environ 5,60€/mois)
- Un environnement Business Central Online (essai 30 jours disponible)
- Accès administrateur à Azure Portal
- Postman (pour tester les APIs)

---

## 🔧 Étape 1 : Créer un Tenant Microsoft 365

### 1.1 S'inscrire à Microsoft 365 Business Basic

1. Allez sur : https://www.microsoft.com/microsoft-365/business/microsoft-365-business-basic
2. Créez votre compte avec une adresse email personnelle
3. Microsoft crée automatiquement votre tenant (ex: `votreentreprise.onmicrosoft.com`)

### 1.2 Ajouter Business Central

1. Connectez-vous à votre Admin Center Microsoft 365
2. Ou allez directement sur : https://trials.dynamics.com/
3. Ajoutez un essai Business Central (30 jours gratuit)
4. Notez votre **Tenant ID** qui apparaît dans l'URL :
   ```
   https://businesscentral.dynamics.com/{TENANT_ID}/admin
   ```

---

## 🔐 Étape 2 : Créer une App Registration dans Azure

### 2.1 Accéder à Azure Portal

1. Connectez-vous à : https://portal.azure.com
2. Recherchez **"Microsoft Entra ID"** (anciennement Azure Active Directory)
3. Dans le menu de gauche, cliquez sur **"App registrations"**

### 2.2 Créer une nouvelle application

1. Cliquez sur **"New registration"**
2. Remplissez les informations :
   - **Name** : "Business Central API Integration"
   - **Supported account types** : "Accounts in this organizational directory only"
   - **Redirect URI** : Laissez vide (optionnel : Web → `https://oauth.pstmn.io/v1/callback` pour Postman)
3. Cliquez sur **"Register"**

### 2.3 Noter le Client ID

1. Sur la page **Overview** de votre application
2. Copiez et sauvegardez l'**Application (client) ID**
   - Format : `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

---

## 🔑 Étape 3 : Créer un Client Secret

### 3.1 Générer le secret

1. Dans votre App Registration, menu de gauche : **"Certificates & secrets"**
2. Cliquez sur **"New client secret"**
3. Remplissez :
   - **Description** : "API Access"
   - **Expires** : 24 months (maximum)
4. Cliquez sur **"Add"**

### 3.2 Copier la Value (CRITIQUE !)

⚠️ **TRÈS IMPORTANT** : Copiez immédiatement la **"Value"** (pas le Secret ID !)

- ✅ **Value** à copier : `XIw8Q~PwVulQpJQ50qafnvMo3khw...` (environ 40 caractères)
- ❌ **Secret ID** (ne PAS utiliser) : `212b1807-66a6-4b0e-87a0-58b8c44c1233`

**Cette Value ne sera plus jamais affichée !** Si vous la perdez, créez un nouveau secret.

---

## 🎯 Étape 4 : Configurer les Permissions API

### 4.1 Ajouter les permissions Business Central

1. Dans votre App Registration, menu : **"API permissions"**
2. Cliquez sur **"Add a permission"**
3. Recherchez et cliquez sur **"Dynamics 365 Business Central"**

### 4.2 Sélectionner les permissions Application

**IMPORTANT** : Choisissez **"Application permissions"** (pas "Delegated permissions")

Cochez les permissions suivantes :
- ☑️ **API.ReadWrite.All** (accès complet aux APIs)
- ☑️ **Automation.ReadWrite.All** (pour les APIs d'automation)

4. Cliquez sur **"Add permissions"**

### 4.3 Accorder le consentement administrateur (CRITIQUE !)

1. Cliquez sur le bouton **"Grant admin consent for [votre organisation]"**
2. Confirmez en cliquant **"Yes"**
3. Vérifiez que le **Status** affiche : ✅ **"Granted for [votre tenant]"** en vert

**Sans cette étape, l'authentification échouera !**

---

## 🏢 Étape 5 : Enregistrer l'Application dans Business Central

### 5.1 Accéder à Business Central

1. Connectez-vous à Business Central : https://businesscentral.dynamics.com
2. Appuyez sur **Alt+Q** ou cliquez sur la loupe 🔍
3. Recherchez : **"Microsoft Entra Applications"** (ou "Azure AD Applications")

### 5.2 Créer l'enregistrement

1. Cliquez sur **"New"** / **"Nouveau"**
2. Remplissez :
   - **Client ID** : Collez votre Client ID d'Azure
   - **Description** : "API Integration"
   - **State** / **Status** : **Enabled** / **Activé**
3. **Sauvegardez** la fiche

Le système remplira automatiquement les champs User ID, Username, etc.

---

## 🧪 Étape 6 : Tester avec Postman

### 6.1 Créer une nouvelle requête

1. Ouvrez Postman
2. Créez une nouvelle requête **GET**
3. URL :
   ```
   https://api.businesscentral.dynamics.com/v2.0/{TENANT_ID}/Production/api/v2.0/companies
   ```
   Remplacez `{TENANT_ID}` par votre Tenant ID

### 6.2 Configurer l'authentification OAuth 2.0

Dans l'onglet **Authorization** :
- **Type** : `OAuth 2.0`
- **Add auth data to** : `Request Headers`

Cliquez sur **"Configure New Token"** :

| Paramètre | Valeur |
|-----------|--------|
| **Token Name** | Business Central Token |
| **Grant Type** | Client Credentials |
| **Access Token URL** | `https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token` |
| **Client ID** | Votre Client ID |
| **Client Secret** | Votre Client Secret Value |
| **Scope** | `https://api.businesscentral.dynamics.com/.default` |
| **Client Authentication** | Send as Basic Auth header |

### 6.3 Obtenir et utiliser le token

1. Cliquez sur **"Get New Access Token"**
2. Postman obtient le token
3. Cliquez sur **"Use Token"**
4. Cliquez sur **"Send"**

### 6.4 Résultat attendu

Vous devriez recevoir un JSON avec la liste des compagnies :

```json
{
    "@odata.context": "https://api.businesscentral.dynamics.com/v2.0/{TENANT_ID}/Production/api/v2.0/$metadata#companies",
    "value": [
        {
            "id": "207217f3-fdb9-f011-af69-6045bde99e23",
            "name": "CRONUS CH",
            "displayName": "",
            ...
        }
    ]
}
```

---

## 📊 Endpoints API Utiles

Remplacez :
- `{TENANT_ID}` par votre Tenant ID
- `{COMPANY_ID}` par l'ID d'une compagnie récupéré précédemment

### Lister les compagnies
```
GET /v2.0/{TENANT_ID}/Production/api/v2.0/companies
```

### Lister les clients
```
GET /v2.0/{TENANT_ID}/Production/api/v2.0/companies({COMPANY_ID})/customers
```

### Lister les articles
```
GET /v2.0/{TENANT_ID}/Production/api/v2.0/companies({COMPANY_ID})/items
```

### Lister les factures de vente
```
GET /v2.0/{TENANT_ID}/Production/api/v2.0/companies({COMPANY_ID})/salesInvoices
```

### Créer un client (POST)
```
POST /v2.0/{TENANT_ID}/Production/api/v2.0/companies({COMPANY_ID})/customers

Body (JSON):
{
  "displayName": "Nouveau Client",
  "type": "Company",
  "phoneNumber": "+41 12 345 6789",
  "email": "client@example.com"
}
```

---

## 🔌 Intégration avec n8n

### Configuration du node HTTP Request dans n8n

1. Ajoutez un node **HTTP Request**
2. **Authentication** : OAuth2
3. **Grant Type** : Client Credentials
4. Paramètres :

| Champ | Valeur |
|-------|--------|
| **Access Token URL** | `https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token` |
| **Client ID** | Votre Client ID |
| **Client Secret** | Votre Client Secret |
| **Scope** | `https://api.businesscentral.dynamics.com/.default` |

5. **URL** : Votre endpoint Business Central
6. **Method** : GET, POST, PATCH, DELETE selon besoin

---

## ❌ Erreurs Courantes et Solutions

### Erreur : "invalid_client" - Secret incorrect

**Message** : `AADSTS7000215: Invalid client secret provided`

**Cause** : Vous avez copié le Secret ID au lieu de la Value

**Solution** : 
1. Recréez un nouveau Client Secret dans Azure
2. Copiez immédiatement la **Value** (pas le Secret ID)
3. Générez un nouveau token dans Postman

---

### Erreur 401 : "Authentication_InvalidCredentials"

**Message** : `The server has rejected the client credentials`

**Causes possibles** :
1. Le "Grant admin consent" n'a pas été fait dans Azure
2. L'application n'est pas enregistrée dans Business Central
3. Vous utilisez "Delegated permissions" au lieu de "Application permissions"

**Solution** :
1. Vérifiez les permissions dans Azure (API permissions)
2. Cliquez sur "Grant admin consent"
3. Vérifiez que les permissions sont de type "Application"
4. Enregistrez l'application dans Business Central (Microsoft Entra Applications)
5. Générez un nouveau token

---

### Erreur : "AADSTS65002: Consent required"

**Message** : `Consent between first party application and first party resource must be configured via preauthorization`

**Cause** : Le consentement administrateur n'a pas été accordé

**Solution** :
1. Dans Azure Portal → App Registration → API permissions
2. Cliquez sur **"Grant admin consent for [votre organisation]"**
3. Vérifiez que le Status est "Granted" en vert
4. Générez un nouveau token dans Postman

---

## 💡 Cas d'Usage d'Automatisation

### 1. Synchronisation CRM → Business Central
- Nouveau client dans CRM → Créer dans BC
- Mise à jour contact → Synchroniser dans BC

### 2. Gestion automatique des commandes
- Commande e-commerce → Créer commande de vente dans BC
- Commande confirmée → Créer facture automatiquement
- Paiement reçu → Marquer facture comme payée

### 3. Rapports et exports automatiques
- Export quotidien des ventes → Google Sheets
- Rapport hebdomadaire des stocks → Email
- Dashboard temps réel avec données BC

### 4. Notifications
- Nouvelle commande → Notification Slack
- Stock faible → Email d'alerte
- Facture impayée > 30 jours → Relance automatique

### 5. Intégration multi-outils
- Zapier / n8n / Power Automate
- Connexion avec systèmes tiers
- Workflows complexes multi-étapes

---

## 📚 Ressources Utiles

### Documentation Microsoft
- [OAuth pour Business Central](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/webservices/authenticate-web-services-using-oauth)
- [Service-to-Service Authentication](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/automation-apis-using-s2s-authentication)
- [Business Central API Reference](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/)

### Outils
- [Postman](https://www.postman.com/) - Test d'APIs
- [n8n](https://n8n.io/) - Automatisation open source
- [Azure Portal](https://portal.azure.com) - Configuration

---

## 📝 Notes Importantes

### Sécurité
- ⚠️ Ne jamais committer les Client Secrets dans Git
- 🔐 Utilisez des variables d'environnement pour les credentials
- 🔄 Renouvelez régulièrement les secrets (max 24 mois)
- 👥 Limitez les permissions au strict nécessaire

### Environnements
- **Production** : Environnement de production Business Central
- **Sandbox** : Environnement de test (recommandé pour développement)

### Limitations
- ⏱️ Les tokens OAuth expirent après 1 heure (renouvellement automatique)
- 📊 Rate limiting : Respectez les limites d'appels API de Microsoft
- 🔄 Basic Auth (Web Service Keys) est **déprécié** depuis 2022

---

## ✅ Checklist de Validation

Avant de passer en production, vérifiez :

- [ ] Tenant Microsoft 365 créé
- [ ] Business Central Online activé
- [ ] App Registration créée dans Azure
- [ ] Client Secret créé et sauvegardé (Value, pas Secret ID)
- [ ] Permissions "Application" ajoutées (API.ReadWrite.All)
- [ ] "Grant admin consent" accordé dans Azure
- [ ] Application enregistrée dans Business Central (Microsoft Entra Applications)
- [ ] Test Postman réussi (liste des compagnies récupérée)
- [ ] Endpoints principaux testés (customers, items, etc.)
- [ ] Configuration n8n ou outil d'automatisation effectuée
- [ ] Documentation des workflows créée

---

## 🤝 Contribution

Ce guide est maintenu par David B. N'hésitez pas à suggérer des améliorations via des Issues ou Pull Requests.

---

## 📄 Licence

Ce guide est fourni à titre informatif. Microsoft, Dynamics 365 et Business Central sont des marques déposées de Microsoft Corporation.

---

**Dernière mise à jour** : Novembre 2025
