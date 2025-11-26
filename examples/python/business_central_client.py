#!/usr/bin/env python3
"""
Exemple simple d'utilisation de l'API Business Central avec OAuth 2.0
"""

import requests
import json
from typing import Dict, Optional

class BusinessCentralAPI:
    """Client pour l'API Business Central"""
    
    def __init__(self, tenant_id: str, client_id: str, client_secret: str, environment: str = "Production"):
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.environment = environment
        self.base_url = f"https://api.businesscentral.dynamics.com/v2.0/{tenant_id}/{environment}/api/v2.0"
        self.token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
        self.access_token: Optional[str] = None
        
    def get_access_token(self) -> str:
        """Obtenir un token OAuth 2.0"""
        data = {
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "scope": "https://api.businesscentral.dynamics.com/.default"
        }
        
        response = requests.post(self.token_url, data=data)
        response.raise_for_status()
        
        token_data = response.json()
        self.access_token = token_data["access_token"]
        return self.access_token
    
    def _get_headers(self) -> Dict[str, str]:
        """Obtenir les headers avec le token"""
        if not self.access_token:
            self.get_access_token()
        
        return {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json"
        }
    
    def get_companies(self) -> Dict:
        """Lister toutes les compagnies"""
        url = f"{self.base_url}/companies"
        response = requests.get(url, headers=self._get_headers())
        response.raise_for_status()
        return response.json()
    
    def get_customers(self, company_id: str) -> Dict:
        """Lister les clients d'une compagnie"""
        url = f"{self.base_url}/companies({company_id})/customers"
        response = requests.get(url, headers=self._get_headers())
        response.raise_for_status()
        return response.json()
    
    def get_items(self, company_id: str) -> Dict:
        """Lister les articles d'une compagnie"""
        url = f"{self.base_url}/companies({company_id})/items"
        response = requests.get(url, headers=self._get_headers())
        response.raise_for_status()
        return response.json()
    
    def create_customer(self, company_id: str, customer_data: Dict) -> Dict:
        """Créer un nouveau client"""
        url = f"{self.base_url}/companies({company_id})/customers"
        response = requests.post(url, headers=self._get_headers(), json=customer_data)
        response.raise_for_status()
        return response.json()


def main():
    """Exemple d'utilisation"""
    
    # Charger la configuration
    with open("config.json", "r") as f:
        config = json.load(f)
    
    bc_config = config["business_central"]
    
    # Créer le client API
    api = BusinessCentralAPI(
        tenant_id=bc_config["tenant_id"],
        client_id=bc_config["client_id"],
        client_secret=bc_config["client_secret"],
        environment=bc_config["environment"]
    )
    
    # Obtenir la liste des compagnies
    print("📊 Récupération des compagnies...")
    companies = api.get_companies()
    
    print(f"\n✅ {len(companies['value'])} compagnie(s) trouvée(s):\n")
    
    for company in companies["value"]:
        company_id = company["id"]
        company_name = company["name"]
        print(f"  • {company_name} (ID: {company_id})")
        
        # Récupérer les clients de cette compagnie
        try:
            customers = api.get_customers(company_id)
            print(f"    → {len(customers['value'])} client(s)")
        except Exception as e:
            print(f"    → Erreur lors de la récupération des clients: {e}")
    
    print("\n✨ Terminé!")


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError:
        print("❌ Erreur: Fichier config.json non trouvé!")
        print("Copiez config.example.json vers config.json et remplissez vos credentials.")
    except Exception as e:
        print(f"❌ Erreur: {e}")
