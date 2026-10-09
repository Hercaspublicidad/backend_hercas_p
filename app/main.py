from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import Settings
from app.core.errors import ServiceError
from app.api.health import router as health_router
from app.api.router import create_api_router


def create_app(settings: Settings | None = None, transport: httpx.AsyncBaseTransport | None = None) -> FastAPI:
    configuration = settings if settings is not None else Settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        async with httpx.AsyncClient(timeout=configuration.HTTP_TIMEOUT_SECONDS, transport=transport) as client:
            application.state.http = client
            yield

    application = FastAPI(
        title=configuration.APP_NAME, version="0.3.0", lifespan=lifespan,
        description="Backend modular de Hercas: identidad compartida, integraciones y módulos de negocio.",
    )
    application.state.settings = configuration

    @application.middleware("http")
    async def private_response_headers(request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                if int(content_length) > configuration.MAX_REQUEST_BODY_BYTES:
                    return JSONResponse(status_code=413, content={"detail": "La solicitud es demasiado grande"})
            except ValueError:
                return JSONResponse(status_code=400, content={"detail": "Solicitud inválida"})
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        response.headers["Cross-Origin-Resource-Policy"] = "same-site"
        return response
    application.add_middleware(
        CORSMiddleware, allow_origins=[*],
        allow_credentials=False, allow_methods=[*],
        allow_headers=[*], max_age=600,
    )

    @application.exception_handler(ServiceError)
    async def service_error_handler(request: Request, error: ServiceError):
        headers = {"WWW-Authenticate": "Bearer"} if error.status_code == 401 else None
        return JSONResponse(status_code=error.status_code, content={"detail": error.detail}, headers=headers)

    @application.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, error: RequestValidationError):
        details = [{"loc": item["loc"], "msg": item["msg"], "type": item["type"]} for item in error.errors()]
        return JSONResponse(status_code=422, content={"detail": details})

    application.include_router(health_router)
    application.include_router(create_api_router(configuration))

    @application.get("/")
    async def root():
        return {"message": configuration.APP_NAME, "version": "0.3.0"}

    return application


app = create_app()
