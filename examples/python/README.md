# Exemple Python - Business Central API

Client Python simple pour interagir avec l'API Business Central via OAuth 2.0.

## 🚀 Installation

1. Installez les dépendances :
```bash
pip install -r requirements.txt
```

2. Copiez le fichier de configuration :
```bash
cp ../../config.example.json ../../config.json
```

3. Remplissez vos credentials dans `config.json`

## 📋 Utilisation

### Exemple de base

```bash
python business_central_client.py
```

Ce script :
- Se connecte à l'API Business Central
- Récupère la liste des compagnies
- Affiche les clients de chaque compagnie

### Utilisation dans votre code

```python
from business_central_client import BusinessCentralAPI

# Créer le client
api = BusinessCentralAPI(
    tenant_id="votre-tenant-id",
    client_id="votre-client-id",
    client_secret="votre-client-secret",
    environment="Production"
)

# Lister les compagnies
companies = api.get_companies()
print(companies)

# Lister les clients d'une compagnie
company_id = companies["value"][0]["id"]
customers = api.get_customers(company_id)
print(customers)

# Créer un nouveau client
new_customer = {
    "displayName": "Test Client",
    "type": "Company",
    "email": "test@example.com"
}
result = api.create_customer(company_id, new_customer)
print(result)
```

## 📚 Méthodes disponibles

### `get_companies()`
Récupère la liste de toutes les compagnies.

**Retour :** Dict contenant la liste des compagnies

### `get_customers(company_id)`
Récupère la liste des clients d'une compagnie.

**Paramètres :**
- `company_id` (str) : ID de la compagnie

**Retour :** Dict contenant la liste des clients

### `get_items(company_id)`
Récupère la liste des articles d'une compagnie.

**Paramètres :**
- `company_id` (str) : ID de la compagnie

**Retour :** Dict contenant la liste des articles

### `create_customer(company_id, customer_data)`
Crée un nouveau client dans une compagnie.

**Paramètres :**
- `company_id` (str) : ID de la compagnie
- `customer_data` (dict) : Données du client

**Retour :** Dict contenant les informations du client créé

## 🔧 Extension

Pour ajouter d'autres endpoints, suivez le pattern :

```python
def get_sales_orders(self, company_id: str) -> Dict:
    """Lister les commandes de vente"""
    url = f"{self.base_url}/companies({company_id})/salesOrders"
    response = requests.get(url, headers=self._get_headers())
    response.raise_for_status()
    return response.json()
```

## 📖 Documentation

Consultez le [Guide de Configuration](../../GUIDE_CONFIGURATION_API.md) pour plus de détails.
