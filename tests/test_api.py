import unittest
from contextlib import ExitStack

import httpx
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app

USER_ID = "11111111-1111-4111-8111-111111111111"


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        self.roles = ["sales"]
        self.active = True
        self.auth_status = 200
        self.data_status = 200
        self.fail_network = False
        self.settings = Settings(_env_file=None, SUPABASE_URL="https://project.example", SUPABASE_PUBLISHABLE_KEY="test-publishable", ODOO_URL="https://odoo.example", ODOO_API_KEY="test-odoo")
        stack = ExitStack()
        self.addCleanup(stack.close)
        self.client = stack.enter_context(TestClient(create_app(self.settings, httpx.MockTransport(self.respond))))
        self.headers = {"Authorization": "Bearer test-user-token"}

    def respond(self, request):
        self.requests.append(request)
        if self.fail_network:
            raise httpx.ConnectError("internal secret", request=request)
        if request.url.path == "/auth/v1/user":
            return httpx.Response(self.auth_status, json={"id": USER_ID, "user_metadata": {"role": "systems_admin"}})
        if request.url.path == "/rest/v1/profiles":
            return httpx.Response(200, json=[{"id": USER_ID, "is_active": self.active}])
        if request.url.path == "/rest/v1/user_roles":
            return httpx.Response(200, json=[{"role": role} for role in self.roles])
        if request.url.path == "/rest/v1/rpc/accept_invitation":
            return httpx.Response(self.data_status, json=USER_ID if self.data_status == 200 else {"message": "internal secret"})
        return httpx.Response(self.data_status, json=[] if self.data_status == 200 else {"message": "internal secret"})

    def test_health_without_external_connection(self):
        self.assertEqual(self.client.get("/health").status_code, 200)
        self.assertFalse(self.requests)

    def test_admin_routes_reject_sales_and_anonymous(self):
        for path, body in [("/api/v1/auth/administracion", None),
                           (f"/api/v1/auth/usuarios/{USER_ID}/acceso", {"roles": ["systems_admin"], "active": True}),
                           ("/api/v1/auth/invitaciones", {"email": "test@example.test", "role": "sales"}),
                           (f"/api/v1/auth/invitaciones/{USER_ID}/enviar", {})]:
            method = self.client.get if body is None else self.client.post
            kwargs = {} if body is None else {"json": body}
            self.assertEqual(method(path, **kwargs).status_code, 401)
            self.assertEqual(method(path, headers=self.headers, **kwargs).status_code, 403)

    def test_access_update_preserves_user_jwt_and_hides_database_errors(self):
        self.roles = ["systems_admin"]
        path = f"/api/v1/auth/usuarios/{USER_ID}/acceso"
        self.assertEqual(self.client.post(path, headers=self.headers, json={"roles": ["sales"], "active": True}).status_code, 200)
        self.assertEqual(self.requests[-1].headers["Authorization"], "Bearer test-user-token")
        self.data_status = 400
        result = self.client.post(path, headers=self.headers, json={"roles": [], "active": False})
        self.assertEqual(result.status_code, 400)
        self.assertNotIn("internal secret", result.text)
        self.assertEqual(result.headers["cache-control"], "no-store")

    def test_invitation_email_requires_server_configuration(self):
        self.roles = ["systems_admin"]
        result = self.client.post(f"/api/v1/auth/invitaciones/{USER_ID}/enviar", headers=self.headers)
        self.assertEqual(result.status_code, 503)
        self.assertFalse(any(r.url.path == "/auth/v1/invite" for r in self.requests))

    def test_invitation_mail_uses_stored_recipient_and_secret_only_for_auth(self):
        self.roles = ["systems_admin"]
        from pydantic import SecretStr
        settings = self.settings.model_copy(update={"SUPABASE_SECRET_KEY": SecretStr("server-secret"), "AUTH_SITE_URL": "https://site.example"})
        def respond(request):
            if request.url.path == "/rest/v1/invitations":
                self.requests.append(request)
                return httpx.Response(200, json=[{"email": "invited@example.test"}])
            if request.url.path == "/auth/v1/invite":
                self.requests.append(request)
                return httpx.Response(200, json={"id": USER_ID})
            return self.respond(request)
        with TestClient(create_app(settings, httpx.MockTransport(respond))) as client:
            result = client.post(f"/api/v1/auth/invitaciones/{USER_ID}/enviar", headers=self.headers)
        self.assertEqual(result.status_code, 200)
        self.assertNotIn("server-secret", result.text)
        mail = self.requests[-1]
        self.assertEqual(mail.headers["apikey"], "server-secret")
        self.assertEqual(mail.url.params["redirect_to"], f"https://site.example/auth/confirmar?invitation={USER_ID}")
        self.assertIn(b"invited@example.test", mail.content)
        self.assertTrue(all(r.headers["apikey"] == "test-publishable" for r in self.requests[:-1]))

    def test_customer_query_reuses_platform_accounts(self):
        response = self.client.get("/api/v1/cotizador/clientes", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        request = self.requests[-1]
        self.assertEqual(request.url.path, "/rest/v1/customer_accounts")
        self.assertIn("legal_name:name", request.url.params["select"])

    def test_calendar_bounds_overlap_filter_and_private_projection(self):
        path = f"/api/v1/cotizador/disponibilidades?asset_id={USER_ID}&starts_on=2027-01-01&ends_on=2027-02-01"
        self.assertEqual(self.client.get(path).status_code, 401)
        self.assertEqual(self.client.get(path, headers=self.headers).status_code, 200)
        request = self.requests[-1]
        self.assertEqual(request.url.path, "/rest/v1/availability_entries")
        self.assertEqual(request.url.params["starts_on"], "lte.2027-02-01")
        self.assertEqual(request.url.params["ends_on"], "gte.2027-01-01")
        self.assertIn("expires_at.gt.", request.url.params["or"])
        self.assertNotIn("evidence_reference", request.url.params["select"])
        self.assertEqual(self.client.get(path.replace("2027-02-01", "2026-01-01"), headers=self.headers).status_code, 422)
        self.assertEqual(self.client.get(path.replace("2027-02-01", "2029-01-01"), headers=self.headers).status_code, 422)

    def test_all_business_routes_require_auth(self):
        for path in ("/api/v1/auth/sesion", "/api/v1/cotizador/productos", "/api/v1/cotizador/inventario", "/api/v1/cotizador/clientes", "/api/v1/cotizador/cotizaciones", "/api/v1/integraciones/odoo/clientes"):
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.headers["www-authenticate"], "Bearer")
        self.assertFalse(self.requests)

    def test_invalid_token_and_inactive_profile(self):
        self.auth_status = 401
        self.assertEqual(self.client.get("/api/v1/auth/sesion", headers=self.headers).status_code, 401)
        self.auth_status = 200
        self.active = False
        self.assertEqual(self.client.get("/api/v1/auth/sesion", headers=self.headers).status_code, 403)

    def test_account_without_roles_has_session_but_no_module_access(self):
        self.roles = []
        response = self.client.get("/api/v1/auth/sesion", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["roles"], [])
        self.assertEqual(self.client.get("/api/v1/cotizador/productos", headers=self.headers).status_code, 403)

    def test_unknown_role_does_not_grant_module_access(self):
        self.roles = ["future_module_role"]
        self.assertEqual(self.client.get("/api/v1/auth/sesion", headers=self.headers).status_code, 200)
        self.assertEqual(self.client.get("/api/v1/cotizador/cotizaciones", headers=self.headers).status_code, 403)

    def test_platform_can_run_without_cotizador(self):
        settings = self.settings.model_copy(update={"ENABLED_MODULES": []})
        with TestClient(create_app(settings, httpx.MockTransport(self.respond))) as client:
            self.assertEqual(client.get("/health").status_code, 200)
            self.assertEqual(client.get("/api/v1/auth/sesion", headers=self.headers).status_code, 200)
            self.assertEqual(client.get("/api/v1/cotizador/productos", headers=self.headers).status_code, 404)
            self.assertEqual(client.get("/api/v1/integraciones/odoo/clientes", headers=self.headers).status_code, 200)

    def test_openapi_separates_platform_module_and_integrations(self):
        schema = self.client.get("/openapi.json").json()
        self.assertEqual(schema["info"]["title"], "Hercas Platform API")
        self.assertIn("/api/v1/auth/sesion", schema["paths"])
        self.assertIn("/api/v1/cotizador/cotizaciones/calcular", schema["paths"])
        self.assertNotIn("/api/v1/cotizaciones/calcular", schema["paths"])

    def test_session_uses_database_roles_and_checks_revocation(self):
        response = self.client.get("/api/v1/auth/sesion", headers=self.headers)
        self.assertEqual(response.json(), {"userId": USER_ID, "roles": ["sales"]})
        self.assertEqual(self.requests[-1].url.params["revoked_at"], "is.null")

    def test_jwt_is_forwarded_to_rls_and_pagination_is_bounded(self):
        response = self.client.get("/api/v1/cotizador/productos?limit=25&offset=50", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        request = self.requests[-1]
        self.assertEqual(request.headers["authorization"], "Bearer test-user-token")
        self.assertEqual(request.headers["apikey"], "test-publishable")
        self.assertEqual(request.url.params["limit"], "25")
        self.assertEqual(request.url.params["offset"], "50")
        self.assertEqual(self.client.get("/api/v1/cotizador/productos?limit=101", headers=self.headers).status_code, 422)

    def test_calculation_contract(self):
        response = self.client.post("/api/v1/cotizador/cotizaciones/calcular", headers=self.headers, json={"rate": 2_000_000, "periods": 2, "additionalLines": [{"quantity": 2, "unitPrice": 300_000}], "discountPercent": 10, "taxPercent": 19})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["total"], 4_926_600)
        self.assertEqual(response.json()["taxableBase"], 4_140_000)

    def test_untrusted_body_is_not_echoed(self):
        response = self.client.post("/api/v1/cotizador/cotizaciones/calcular", headers=self.headers, json={"additionalLines": [], "discountPercent": 0, "taxPercent": 0, "unexpected": "secret-value"})
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("secret-value", response.text)

    def test_sales_cannot_simulate_price_books(self):
        from test_domain import book_data
        response = self.client.post("/api/v1/cotizador/tarifas/simular", headers=self.headers, json={"priceBook": book_data(), "input": {"productId": "v1", "commercialLine": "OOH", "customerKey": "otro", "customerType": "agency", "quotedOn": "2026-09-09"}})
        self.assertEqual(response.status_code, 403)

    def test_pricing_manager_can_simulate(self):
        from test_domain import book_data
        self.roles = ["pricing_manager"]
        response = self.client.post("/api/v1/cotizador/tarifas/simular", headers=self.headers, json={"priceBook": book_data(), "input": {"productId": "v1", "commercialLine": "OOH", "customerKey": "otro", "customerType": "agency", "quotedOn": "2026-09-09"}})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["price"], 9_000_000)

    def test_upstream_errors_are_sanitized(self):
        self.data_status = 500
        response = self.client.get("/api/v1/cotizador/productos", headers=self.headers)
        self.assertEqual(response.status_code, 502)
        self.assertNotIn("internal secret", response.text)
        self.fail_network = True
        response = self.client.get("/api/v1/auth/sesion", headers=self.headers)
        self.assertEqual(response.status_code, 502)
        self.assertNotIn("internal secret", response.text)

    def test_missing_configuration_returns_503(self):
        with TestClient(create_app(Settings(_env_file=None))) as client:
            self.assertEqual(client.get("/health").status_code, 200)
            self.assertEqual(client.get("/api/v1/auth/sesion", headers=self.headers).status_code, 503)

    def test_missing_quote_and_invalid_identifier(self):
        self.assertEqual(self.client.get(f"/api/v1/cotizador/cotizaciones/{USER_ID}", headers=self.headers).status_code, 404)
        self.assertEqual(self.client.get("/api/v1/cotizador/cotizaciones/invalid", headers=self.headers).status_code, 422)

    def test_inventory_projection_excludes_private_evidence(self):
        self.client.get("/api/v1/cotizador/inventario", headers=self.headers)
        fields = self.requests[-1].url.params["select"]
        self.assertNotIn("source_metadata", fields)
        self.assertNotIn("*", fields)

    def test_odoo_errors_are_sanitized_and_limit_validated(self):
        self.data_status = 500
        response = self.client.get("/api/v1/integraciones/odoo/clientes", headers=self.headers)
        self.assertEqual(response.status_code, 502)
        self.assertNotIn("internal secret", response.text)
        self.assertEqual(self.client.get("/api/v1/integraciones/odoo/clientes?limit=-1", headers=self.headers).status_code, 422)

    def test_cors_allows_only_configured_frontend(self):
        response = self.client.options("/api/v1/cotizador/productos", headers={"Origin": "http://localhost:3000", "Access-Control-Request-Method": "GET", "Access-Control-Request-Headers": "authorization"})
        self.assertEqual(response.headers["access-control-allow-origin"], "http://localhost:3000")
        response = self.client.options("/api/v1/cotizador/productos", headers={"Origin": "https://unknown.example", "Access-Control-Request-Method": "GET"})
        self.assertNotIn("access-control-allow-origin", response.headers)

    def test_pending_identity_can_reach_acceptance_but_not_business_session(self):
        self.active = False
        self.assertEqual(self.client.get("/api/v1/auth/sesion", headers=self.headers).status_code, 403)
        response = self.client.post(f"/api/v1/auth/invitaciones/{USER_ID}/aceptar", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"invitationId": USER_ID})
        self.assertEqual(self.requests[-1].method, "POST")
        self.assertEqual(self.requests[-1].headers["authorization"], "Bearer test-user-token")

    def test_invitation_rejection_is_not_reported_as_accepted(self):
        self.data_status = 403
        response = self.client.post(f"/api/v1/auth/invitaciones/{USER_ID}/aceptar", headers=self.headers)
        self.assertEqual(response.status_code, 403)
        self.assertNotIn("internal secret", response.text)
        self.assertEqual(self.client.post(f"/api/v1/auth/invitaciones/{USER_ID}/aceptar").status_code, 401)

    def test_customer_account_without_staff_roles_can_query_own_companies(self):
        self.roles = []
        self.assertEqual(self.client.get("/api/v1/auth/empresas", headers=self.headers).status_code, 200)
        self.assertEqual(self.requests[-1].url.path, "/rest/v1/customer_accounts")
        self.assertEqual(self.requests[-1].url.params["select"], "id,name")

    def test_api_rejects_oversized_request_before_processing(self):
        response = self.client.post(
            "/api/v1/auth/invitaciones",
            headers={
                **self.headers,
                "Content-Length": "1048577",
            },
            content=b"{}",
        )

        self.assertEqual(response.status_code, 413)
        self.assertFalse(self.requests)


    def test_auth_rejects_oversized_bearer_token(self):
        response = self.client.get(
            "/api/v1/auth/sesion",
            headers={
                "Authorization": f"Bearer {'a' * 9000}",
            },
        )

        self.assertEqual(response.status_code, 401)
        self.assertFalse(self.requests)


    def test_security_headers_are_returned(self):
        response = self.client.get("/health")

        self.assertEqual(response.headers["cache-control"], "no-store")
        self.assertEqual(
            response.headers["x-content-type-options"],
            "nosniff",
        )
        self.assertEqual(response.headers["x-frame-options"], "DENY")
        self.assertEqual(
            response.headers["referrer-policy"],
            "no-referrer",
        )
        self.assertEqual(
            response.headers["cross-origin-resource-policy"],
            "same-site",
        )


    def test_readiness_checks_supabase(self):
        response = self.client.get("/ready")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "status": "ready",
                "supabase": "available",
            },
        )
        self.assertEqual(
            self.requests[-1].url.path,
            "/auth/v1/health",
        )


    def test_docs_can_be_disabled(self):
        settings = self.settings.model_copy(
            update={"API_DOCS_ENABLED": False}
        )

        with TestClient(
            create_app(
                settings,
                httpx.MockTransport(self.respond),
            )
        ) as client:
            self.assertEqual(client.get("/docs").status_code, 404)
            self.assertEqual(
                client.get("/openapi.json").status_code,
                404,
            )


    def test_supabase_rate_limit_is_preserved(self):
        self.data_status = 429

        response = self.client.get(
            "/api/v1/cotizador/productos",
            headers=self.headers,
        )

        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.headers["retry-after"], "60")
        self.assertNotIn("internal secret", response.text)

        
