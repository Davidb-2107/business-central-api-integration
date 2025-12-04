# Spécification : Ajout du champ Mandat dans QR-Reader

## Contexte

L'application QR-Reader scanne des factures PDF avec QR-code suisse et envoie les données à Business Central via un workflow n8n. 

Certains fournisseurs ajoutent un numéro de client (ex: "Client N° : _764") sur leurs factures qui correspond à un code **MANDAT** dans Business Central. Ce code permet d'assigner automatiquement la bonne dimension analytique à la facture.

## Objectif

Ajouter un champ optionnel "Mandat" dans l'interface QR-Reader permettant à l'utilisateur de saisir le code mandat avant d'envoyer vers Business Central.

## Spécifications fonctionnelles

### Interface utilisateur

Ajouter un champ de saisie optionnel après les données extraites du QR-code :

```
┌─────────────────────────────────────────────────┐
│  QR-Reader                                       │
├─────────────────────────────────────────────────┤
│                                                  │
│  Données extraites du QR-code :                  │
│  ─────────────────────────────                   │
│  Fournisseur : CENTRE PATRONAL                   │
│  Adresse : Route du Lac 2, 1094 Paudex           │
│  Montant : 18'250.00 CHF                         │
│  Référence : 000000000000002250627109240         │
│                                                  │
│  ─────────────────────────────                   │
│  Informations complémentaires :                  │
│                                                  │
│  Mandat : [ 764                            ]     │
│           (optionnel - code client fournisseur)  │
│                                                  │
│  [        Envoyer vers Business Central        ] │
│                                                  │
└─────────────────────────────────────────────────┘
```

### Comportement

1. Le champ "Mandat" est **optionnel** (peut rester vide)
2. Le champ accepte des valeurs alphanumériques (ex: "764", "M001", "ABC-123")
3. Pas de validation côté client (la validation se fait dans Business Central)
4. Le champ est conservé pour la session mais pas persisté

### Données envoyées au webhook

Le payload JSON envoyé à n8n doit inclure le nouveau champ `mandat` :

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

Si le champ est vide, envoyer une chaîne vide :
```json
{
  "parsedData": {
    ...
    "mandat": ""
  }
}
```

## Spécifications techniques

### Composant React (si applicable)

```jsx
// Exemple de structure pour le champ Mandat
const [mandat, setMandat] = useState('');

// Dans le JSX
<div className="form-group">
  <label htmlFor="mandat">Mandat</label>
  <input
    type="text"
    id="mandat"
    value={mandat}
    onChange={(e) => setMandat(e.target.value)}
    placeholder="Code client fournisseur (optionnel)"
    maxLength={20}
  />
  <small>Optionnel - Correspond au numéro de client chez le fournisseur</small>
</div>

// Dans la fonction d'envoi
const payload = {
  parsedData: {
    ...existingData,
    mandat: mandat.trim()
  }
};
```

### Endpoint webhook

L'URL du webhook n8n ne change pas. Seul le payload est enrichi du champ `mandat`.

## Tests à effectuer

1. **Champ vide** : Envoyer sans remplir le champ mandat → doit fonctionner
2. **Champ rempli** : Envoyer avec "764" → doit apparaître dans le payload
3. **Caractères spéciaux** : Tester avec "ABC-123" → doit être accepté
4. **Longueur** : Tester avec 20 caractères → doit être accepté

## Évolution future (hors scope actuel)

- OCR automatique pour détecter "Client N°" sur la facture
- Liste déroulante avec les mandats connus
- Mémorisation du mandat par fournisseur

## Référence

Documentation complète de l'intégration Business Central :
https://github.com/Davidb-2107/business-central-api-integration
