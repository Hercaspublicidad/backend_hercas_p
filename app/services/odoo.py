import httpx

from app.config import settings


class OdooClient:

    def __init__(self):

        self.base_url = settings.ODOO_URL.rstrip("/")
        self.api_key = settings.ODOO_API_KEY
        self.database = settings.ODOO_DATABASE

    def _headers(self):

        headers = {
            "Authorization": f"bearer {self.api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Hercas-Sistema-Externos/1.0"
        }

        if self.database:
            headers["X-Odoo-Database"] = self.database

        return headers

    async def call(
        self,
        model: str,
        method: str,
        data: dict | None = None
    ):

        url = f"{self.base_url}/json/2/{model}/{method}"

        async with httpx.AsyncClient(timeout=30.0) as client:

            response = await client.post(
                url,
                headers=self._headers(),
                json=data or {}
            )

            response.raise_for_status()

            return response.json()
        

    def odoo () :
        pass    


odoo = OdooClient()