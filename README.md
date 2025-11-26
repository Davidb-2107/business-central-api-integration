# 🚀 Business Central API Integration

Guide complet pour intégrer Microsoft Dynamics 365 Business Central avec des outils d'automatisation via OAuth 2.0.

## 📖 À propos

Ce repository contient la documentation complète pour configurer l'accès aux APIs de Business Central Online en utilisant l'authentification OAuth 2.0 (Service-to-Service). Cette configuration permet l'automatisation et l'intégration avec des outils comme n8n, Power Automate, Zapier, et plus encore.

## 📚 Documentation

### [📘 Guide de Configuration Complet](./GUIDE_CONFIGURATION_API.md)

Le guide couvre :
- ✅ Configuration du tenant Microsoft 365
- 🔐 Création de l'App Registration dans Azure
- 🔑 Configuration des permissions OAuth 2.0
- 🧪 Tests avec Postman
- 🔌 Intégration avec n8n
- ❌ Résolution des erreurs courantes
- 💡 Cas d'usage d'automatisation

## 🎯 Cas d'Usage

Ce guide vous permet de :
- Synchroniser Business Central avec votre CRM
- Automatiser la création de factures
- Exporter des données vers Excel/Google Sheets
- Créer des notifications automatiques (Slack, Email)
- Intégrer BC avec des systèmes tiers

## ⚡ Démarrage Rapide

1. Créez un tenant Microsoft 365 Business
2. Ajoutez Business Central Online (essai 30 jours)
3. Suivez le [guide de configuration](./GUIDE_CONFIGURATION_API.md)
4. Testez avec Postman
5. Commencez vos automatisations !

## 🛠️ Technologies

- Microsoft Dynamics 365 Business Central Online
- OAuth 2.0 (Client Credentials Flow)
- Microsoft Entra ID (Azure AD)
- Postman (tests)
- n8n (automatisation)

## 📋 Prérequis

- Compte Microsoft 365 Business (~5,60€/mois)
- Environnement Business Central Online
- Accès administrateur Azure Portal
- Postman (gratuit)

## 🔗 Ressources Utiles

### Documentation Microsoft
- [OAuth pour Business Central](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/webservices/authenticate-web-services-using-oauth)
- [Service-to-Service Authentication](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/automation-apis-using-s2s-authentication)
- [Business Central API Reference](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/)

### Outils
- [Postman](https://www.postman.com/)
- [n8n](https://n8n.io/)
- [Azure Portal](https://portal.azure.com)

## ⚠️ Notes Importantes

- 🔐 Ne jamais committer les secrets dans Git
- 🔄 Les tokens expirent après 1 heure (renouvellement automatique)
- ⚡ Respectez les limites d'appels API de Microsoft
- 📊 Basic Auth est déprécié depuis 2022

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
