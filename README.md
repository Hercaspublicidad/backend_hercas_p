# Hercas — backend del sitio web

FastAPI es el backend compartido del sitio; el cotizador es su primer módulo.
Next.js conserva la interfaz. Supabase proporciona una identidad por usuario,
autenticación y PostgreSQL. Los roles determinan qué módulos y operaciones puede
usar cada cuenta: iniciar sesión no concede automáticamente permisos comerciales.

La propuesta de arquitectura y el plan están en [docs/arquitectura.md](docs/arquitectura.md).
La protección ante ataques web, abuso automatizado y manipulación del agente se
define en [docs/seguridad.md](docs/seguridad.md), con controles y pruebas pendientes.
La primera migración de usuarios, empresas cliente, roles, permisos e invitaciones
está aplicada en `hercas-platform-dev` desde el 17 de septiembre de 2026.
Se verificaron RLS y privilegios de las nueve tablas. Ver
[supabase/README.md](supabase/README.md) para pruebas y configuración de Auth pendiente.
También está aplicada la [base de cotizador y disponibilidad](supabase/COTIZADOR.md),
con catálogo, versiones de precios, cotizaciones y calendario. La base inicial
contiene 18 tablas con RLS. La integración operativa de cotizaciones con Odoo y
el guardado transaccional por API siguen pendientes.

La rama `main` conserva las migraciones de catálogo y disponibilidad recuperadas
de `origin/disponibilidad` y las tres migraciones posteriores de canje, vencimiento
de reservas manuales a 72 horas y privacidad pública (hasta
`20261001221500_availability_barter_public_privacy.sql`).
Esto integra el historial de código; no aplica por sí mismo migraciones a otro
proyecto Supabase ni valida un despliegue nuevo.

**Prioridades de diseño: seguridad, web pública rápida y SEO.** Los módulos privados cargan solo
en sus rutas; renders, reportes pesados y automatizaciones se ejecutarán fuera de
la API web en trabajos controlados. La arquitectura incluye caché de contenido
público, presupuestos de carga, controles de indexación y medición de Core Web
Vitals. Son requisitos: todavía no se ha medido ni optimizado el frontend.

Alcance confirmado de la plataforma: **usuarios, cotizador, reportes internos y
para clientes, pagos, CMS, blogs con redes sociales automatizadas y agente de
respuesta**. Blogs incluye estrategia editorial, calendario, aprobación, programación,
publicación por canal y métricas; las integraciones concretas están por definir.
También se incluye la programación de campañas en un circuito de pantallas digitales
de la ciudad. Dentro del cotizador se planifican disponibilidades y se gestionan
renders de productos solicitados por clientes. La operación de pantallas se propone
como capacidad separada, conectada a las reservas del cotizador y a Reportes.
Se planifica que el agente registre interesados de la web en el CRM de Odoo,
mediante captación validada, prevención de duplicados y seguimiento de sincronización.
Esta capacidad todavía no está implementada.
La disponibilidad será mantenida por su encargada en la plataforma y el rol de
administrador de precios del cotizador gestionará las tarifas por producto. Cotizador, web y agente usarán esos datos
vigentes, con permisos separados e historial. Los paneles y la actualización en
vivo están definidos en arquitectura y pendientes de implementación.
Odoo alimentará los datos
empresariales; la arquitectura define qué datos son propios de la plataforma.
Actualmente solo hay una base técnica de autenticación/integraciones y una
implementación parcial del cotizador; los demás módulos están en planificación.

## Organización modular

```text
app/
  main.py                  # Arranque y recursos del proceso
  core/                    # Configuración, sesión y errores compartidos
  api/                     # Composición de rutas, salud y autenticación
  integrations/
    supabase/              # Cliente con JWT y RLS
    odoo/                  # Acceso compartido a Odoo
  modules/
    cotizador/
      router.py            # API del módulo y permisos
      domain/              # Cálculos, tarifas y reglas temporales
```

`ENABLED_MODULES=["cotizador"]` habilita el módulo; `ENABLED_MODULES=[]` permite
ejecutar la plataforma con autenticación e integraciones sin el cotizador.
Un perfil activo sin roles puede consultar su sesión, pero no entrar al cotizador.
Los roles actuales son los del esquema piloto; los permisos por módulo se definirán
en la siguiente etapa de arquitectura antes de crear las tablas definitivas.

Las rutas iniciales cambiaron: sesión en `/api/v1/auth/sesion`, cotizador bajo
`/api/v1/cotizador` y Odoo bajo `/api/v1/integraciones/odoo`. No hay alias para las
rutas anteriores. No se ha conectado todavía un frontend a estas rutas.
El nombre por defecto es `Hercas Platform API`; un APP_NAME definido en el `.env`
existente tiene prioridad y puede actualizarse sin cambiar credenciales.

## Estado de la migración

Implementado en este corte:

- Motor Python de cálculo de cotizaciones COP, prioridad de acuerdos de cliente,
  validación de tarifas, fechas y porcentajes.
- Reglas puras de separación de 72 horas, solapamiento inclusivo y validación de reserva.
- Simulaciones HTTP autenticadas, sesión y consultas paginadas a Supabase.
- Validación del JWT en Supabase Auth y perfil activo/roles no revocados en la BD.
- Conservación del JWT en las consultas para que se apliquen las políticas RLS.
- Cliente Odoo con errores públicos sanitizados y límite de consulta acotado.
- Pruebas locales del dominio y de HTTP con servicios externos simulados.

Pendiente: conexión y verificación contra el nuevo proyecto Supabase, revisión y
aplicación de migraciones, escritura transaccional de cotizaciones, publicación de
tarifas, bloqueo concurrente de inventario, pantallas de autenticación y conexión
del frontend. No hay todavía un flujo de cotización persistente listo para producción.

## Ejecutar en Windows

Python 3.10 o posterior. Desde la raíz:

```powershell
.\venv_apiodoo\Scripts\python.exe -m pip install -r app/requirements.txt
.\venv_apiodoo\Scripts\python.exe -m uvicorn app.main:app --reload
```

Documentación interactiva: http://127.0.0.1:8000/docs

Conservar el `.env` existente. Agregar únicamente las variables que falten usando
`.env.example` como referencia; no sobrescribir las credenciales Odoo.

```dotenv
SUPABASE_URL=https://PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_REEMPLAZAR
CORS_ORIGINS=["http://localhost:3000"]
```

La clave publishable identifica el proyecto, no al usuario. Las rutas de negocio
requieren `Authorization: Bearer <access_token>` de una sesión Supabase Auth.
También se acepta una clave legacy anon en SUPABASE_PUBLISHABLE_KEY.
No usar service_role ni secret key: este adaptador está diseñado para RLS con la
identidad del usuario. Las contraseñas pertenecen a Supabase Auth, no a profiles.

Sin Supabase configurado arrancan `/`, `/health` y `/docs`; las rutas de negocio
devuelven 401 sin sesión o 503 si se proporciona token y falta configuración.
`/health` verifica únicamente que el proceso responde, no la conexión a las bases.
La ruta existente `/api/v1/integraciones/odoo/clientes` ahora requiere sesión y rol sales/systems_admin.

## API inicial

| Ruta | Comportamiento |
| --- | --- |
| GET /api/v1/auth/sesion | Identidad y roles activos |
| POST /api/v1/cotizador/cotizaciones/calcular | Simula importes; no guarda ni autoriza descuentos |
| POST /api/v1/cotizador/tarifas/simular | Simula el tarifario recibido; requiere pricing_manager/systems_admin |
| GET /api/v1/cotizador/productos | Productos activos visibles |
| GET /api/v1/cotizador/inventario | Activos visibles y vigentes; no equivale a disponibilidad por fechas |
| GET /api/v1/cotizador/clientes | Clientes activos accesibles por RLS |
| GET /api/v1/cotizador/cotizaciones | Cabeceras accesibles por RLS |
| GET /api/v1/cotizador/cotizaciones/{uuid} | Cabecera de una cotización accesible por RLS |

Listados: `limit` entre 1 y 100, `offset` no negativo. Las consultas devuelven los
nombres de columnas de Supabase (snake_case) y sus UUID. Las simulaciones conservan
camelCase del piloto. Los IDs Odoo, IDs locales del piloto y UUID de Supabase no son
intercambiables; el futuro adaptador del frontend deberá mapearlos explícitamente.

Ejemplo del cuerpo de `/api/v1/cotizador/cotizaciones/calcular`:

```json
{
  "rentalLines": [{"unitPrice": 2000000, "periods": 2}],
  "additionalLines": [{"quantity": 2, "unitPrice": 300000}],
  "discountPercent": 10,
  "taxPercent": 19
}
```

Resultado esperado: total 4926600 COP. Los importes de una simulación nunca deben
reutilizarse como valores confiables al guardar; el servidor debe resolver los
precios oficiales a partir de las fuentes autorizadas.

## Verificar

```powershell
.\venv_apiodoo\Scripts\python.exe -m unittest discover -s tests -v
```

No usa ni modifica servicios reales. Verifica casos del piloto, redondeo de medios
pesos, precedencia de reglas, vencimiento, validación, autenticación, roles,
propagación del JWT, CORS y errores externos. Las políticas SQL requieren además
pruebas en Supabase antes de habilitar escrituras.

## Referencia y decisiones pendientes

Fuente: `app/.worktrees/supabase-inventario-vallas`. No se modificó ese worktree.
Ver `docs/migracion.md` para diferencias entre dominio y esquema.

Documentación consultada:
[Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys),
[seguridad de Data API](https://supabase.com/docs/guides/api/securing-your-api),
[validación de usuario](https://supabase.com/docs/reference/python/auth-getuser),
[pruebas FastAPI](https://fastapi.tiangolo.com/tutorial/testing/).
