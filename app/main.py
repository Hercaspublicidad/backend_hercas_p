from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.health import router as health_router
from app.api.router import create_api_router
from app.core.config import Settings
from app.core.errors import ServiceError


def create_app(
    settings: Settings | None = None,
    transport: httpx.AsyncBaseTransport | None = None,
) -> FastAPI:
    configuration = settings if settings is not None else Settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        async with httpx.AsyncClient(
            timeout=configuration.HTTP_TIMEOUT_SECONDS,
            transport=transport,
        ) as client:
            application.state.http = client
            yield

    application = FastAPI(
        title=configuration.APP_NAME,
        version="0.3.0",
        lifespan=lifespan,
        description=(
            "Backend modular de Hercas: identidad compartida, "
            "integraciones y módulos de negocio."
        ),
        docs_url="/docs" if configuration.API_DOCS_ENABLED else None,
        redoc_url="/redoc" if configuration.API_DOCS_ENABLED else None,
        openapi_url=(
            "/openapi.json"
            if configuration.API_DOCS_ENABLED
            else None
        ),
    )

    application.state.settings = configuration

    @application.middleware("http")
    async def security_and_request_limits(request: Request, call_next):
        content_length = request.headers.get("content-length")
        response = None

        if content_length:
            try:
                request_size = int(content_length)
            except ValueError:
                response = JSONResponse(
                    status_code=400,
                    content={"detail": "Solicitud inválida"},
                )
            else:
                if request_size < 0:
                    response = JSONResponse(
                        status_code=400,
                        content={"detail": "Solicitud inválida"},
                    )
                elif request_size > configuration.MAX_REQUEST_BODY_BYTES:
                    response = JSONResponse(
                        status_code=413,
                        content={
                            "detail": "La solicitud es demasiado grande"
                        },
                    )

        if response is None:
            response = await call_next(request)

        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = (
            "camera=(), microphone=(), geolocation=()"
        )
        response.headers["Cross-Origin-Resource-Policy"] = "same-site"

        return response

    application.add_middleware(
        CORSMiddleware,
        allow_origins=configuration.CORS_ORIGINS,
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
        max_age=600,
    )

    @application.exception_handler(ServiceError)
    async def service_error_handler(
        request: Request,
        error: ServiceError,
    ):
        headers: dict[str, str] = {}

        if error.status_code == 401:
            headers["WWW-Authenticate"] = "Bearer"

        if error.status_code == 429:
            headers["Retry-After"] = "60"

        return JSONResponse(
            status_code=error.status_code,
            content={"detail": error.detail},
            headers=headers or None,
        )

    @application.exception_handler(RequestValidationError)
    async def validation_error_handler(
        request: Request,
        error: RequestValidationError,
    ):
        details = [
            {
                "loc": item["loc"],
                "msg": item["msg"],
                "type": item["type"],
            }
            for item in error.errors()
        ]

        return JSONResponse(
            status_code=422,
            content={"detail": details},
        )

    application.include_router(health_router)
    application.include_router(create_api_router(configuration))

    @application.get("/")
    async def root():
        return {
            "message": configuration.APP_NAME,
            "version": "0.3.0",
        }

    return application


app = create_app()