# QR-Reader App

Application React pour scanner des factures QR suisses et les envoyer vers Business Central via un webhook n8n.

## Fonctionnalités

- Scanner des factures PDF avec QR-code suisse
- Affichage des données extraites (fournisseur, montant, référence)
- Champ **Mandat** optionnel pour le code client fournisseur
- Envoi vers Business Central via webhook n8n

## Le champ Mandat

Le champ Mandat permet de saisir le numéro de client chez le fournisseur (ex: "Client N° : 764" sur la facture). Ce code est utilisé dans Business Central pour assigner automatiquement la bonne dimension analytique à la facture.

### Caractéristiques
- Champ optionnel (peut rester vide)
- Accepte des valeurs alphanumériques (ex: "764", "M001", "ABC-123")
- Maximum 20 caractères
- Inclus dans le payload JSON envoyé au webhook

## Installation

```bash
cd qr-reader-app
npm install
```

## Configuration

1. Copier le fichier `.env.example` vers `.env`
2. Configurer l'URL du webhook n8n :

```bash
cp .env.example .env
```

Éditer `.env` :
```
VITE_WEBHOOK_URL=https://votre-instance-n8n.com/webhook/qr-reader
```

## Développement

```bash
npm run dev
```

L'application sera accessible sur http://localhost:3000

## Production

```bash
npm run build
```

Les fichiers de production seront dans le dossier `dist/`.

## Payload JSON envoyé

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
    "qr_reference_(qrr)": "000000000000002250627109240",
    "mandat": "764"
  }
}
```

## Structure du projet

```
qr-reader-app/
├── index.html
├── package.json
├── vite.config.js
├── .env.example
└── src/
    ├── main.jsx
    ├── App.jsx
    ├── components/
    │   └── QRReader.jsx
    └── styles/
        ├── index.css
        └── QRReader.css
```

## Technologies

- React 18
- Vite 5
- CSS Modules

## Voir aussi

- [Spécification du champ Mandat](../docs/QR_READER_MANDAT_SPEC.md)
- [Guide Configuration API](../GUIDE_CONFIGURATION_API.md)
- [Guide Extension AL](../GUIDE_AL_EXTENSION.md)
