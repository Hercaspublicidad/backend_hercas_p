# Plan de seguridad — plataforma Hercas

Requisito confirmado: protección frente a ataques web, abuso automatizado y ataques
que utilicen agentes de IA o intenten manipular el agente del sitio. Este documento
define controles y verificación; no certifica protección desplegada ni inmunidad.

## Principios

Validar identidad, permiso, propiedad y límites de cada solicitud, provenga de una
persona, bot o agente. No depender de detectar si el atacante usa IA. Denegar lo
no autorizado, reducir privilegios, limitar consumo y permitir revocación rápida.

Conservar rendimiento y SEO: filtrar abuso en perímetro/backend, evitando scripts
pesados y desafíos indiscriminados para visitantes. No bloquear rastreadores
legítimos por defecto ni confiar en su User-Agent. CORS y robots.txt no autorizan
acceso ni protegen datos privados.

## Controles previstos

| Capa | Controles | Verificación |
| --- | --- | --- |
| Perímetro | HTTPS, WAF/DDoS según alojamiento, límites de solicitudes y tamaño, restricción de acceso directo al origen | Rechazos y continuidad de páginas públicas |
| Identidad | MFA para cuentas privilegiadas, sesiones verificadas, revocación y protección de login/recuperación contra abuso | Sesión expirada, perfil desactivado y permisos revocados |
| API/datos | Permisos por acción/recurso, pertenencia a empresa cliente, RLS, campos explícitos y consultas parametrizadas | Dos clientes no pueden leer, modificar ni exportar datos del otro |
| Contenido | Codificación de salida, saneamiento de HTML, CSP y protección contra incrustación; CSRF si se usan cookies para autenticar | CMS, blogs y salidas del agente no ejecutan contenido malicioso |
| Archivos/renders | Límites de tamaño y tipo real, cuarentena/análisis según formato, procesos aislados con cuotas de CPU/memoria/tiempo | Archivos falsificados, descompresión excesiva y cancelación de trabajos |
| Integraciones | Credenciales solo servidor, mínimo privilegio, destinos autorizados y tiempos de espera | Fallos externos sin fuga de secretos |
| Operación | Revisión de dependencias y secretos, actualizaciones, auditoría, copias y restauración probada | Alertas útiles y recuperación verificable |

Los límites deben funcionar entre instancias, no solo en memoria del proceso.
Aplicarlos por usuario/empresa, recurso y operación además de IP. Confiar en
cabeceras de IP reenviada únicamente desde proxies conocidos.

## Abuso del negocio y costos

Definir cuotas de concurrencia, trabajos pendientes, almacenamiento, tokens y
generaciones por cuenta. Acotar cuerpo, adjuntos, resultados y duración. Limitar
separaciones de inventario para evitar que una cuenta bloquee toda la capacidad.
Verificar expiración, transiciones e idempotencia de reservas, cobros y publicaciones.
Poder pausar una integración o generación abusada sin apagar el contenido público.
Dimensionar cifras antes de producción; no inventar límites universales.

## Protección del agente de respuesta

Mensajes, documentos, páginas y resultados de herramientas son datos no confiables:
pueden contener instrucciones maliciosas. Un prompt de seguridad no sustituye los
controles del backend.

1. Cada herramienta comprueba la sesión, permiso e IDs autorizados del usuario.
   El modelo no decide identidad ni puede elevar privilegios.
2. Empezar con lecturas tipadas y acotadas. No conceder SQL arbitrario, shell,
   acceso libre a archivos/red interna ni métodos Odoo genéricos.
3. Filtrar fuentes privadas antes de recuperar información; aislar conversaciones,
   índices, cachés y archivos entre clientes. Comprobar también la salida.
4. No colocar secretos en el contexto. Restringir destinos de red, redirecciones y
   descargas; bloquear URLs privadas, metadatos de infraestructura y protocolos no
   autorizados al procesar enlaces proporcionados por usuarios/documentos.
5. Validar argumentos y sanear respuestas. No ejecutar código o acciones por el
   solo hecho de que el modelo los genere.
6. Cobrar, reservar, publicar o modificar requiere permisos y reglas del módulo.
   Si una acción requiere confirmación, asociarla a parámetros y versión concretos;
   el modelo no puede confirmar por el usuario ni reutilizar una aprobación después
   de cambiar importe, recurso, destino o contenido.
7. Limitar llamadas, tokens, tiempo y profundidad; auditar acciones sin registrar
   credenciales ni contenido privado innecesario.

Probar inyección directa e indirecta, extracción de datos de otro cliente, URLs
internas, acciones sin permiso y agotamiento de recursos. Las barreras deben seguir
funcionando aunque el modelo obedezca un texto malicioso.

## Aplicación a los módulos

- **Pagos:** verificar eventos según el proveedor, importe, moneda, documento y
  cuenta; evitar efectos repetidos. La página de retorno no confirma un pago. Los
  webhooks usan autenticación del proveedor y límites propios.
- **Redes/pantallas:** separar edición, aprobación y publicación; autorizar versión
  y destinos exactos. Proteger credenciales de cuentas/dispositivos y permitir
  revocación. Adaptar la protección de comandos al reproductor real.
- **Odoo:** cuenta técnica limitada y operaciones concretas. FastAPI verifica el
  alcance del cliente aunque esa cuenta técnica pueda ver más información. RLS de
  Supabase no protege automáticamente los datos consultados en Odoo.
- **Reportes/renders:** exigir permiso al consultar estado y descargar resultados;
  recursos privados y acceso temporal según corresponda. Una URL difícil de
  adivinar no sustituye autorización.
- **Captación CRM por el agente:** herramienta de alcance limitado, campos
  permitidos, idempotencia y controles antiabuso. Un correo/teléfono no prueba
  identidad ni autoriza a consultar contactos existentes. No revelar coincidencias
  del CRM al visitante ni permitir modificaciones de etapas, roles o asignaciones
  mediante instrucciones libres del modelo.

## Criterios de entrega y respuesta

Cada módulo necesita pruebas de acceso permitido/denegado, propiedad, validación,
límites y fallos externos. Antes de producción verificar RLS en una base real de
pruebas, aislamiento por cliente, perímetro, sesiones y consumo bajo carga controlada.
Las pruebas de ataques se realizan solo en entornos propios/autorizados.

Alertar sobre accesos anómalos, cambios de privilegios, fallos repetidos, consumo
excesivo y operaciones duplicadas. Definir responsable y procedimiento para contener,
revocar sesiones/credenciales afectadas, conservar evidencia mínima, corregir y
restaurar. Comprobar recuperación, no solo que existen backups.

## Estado real

Ya existen validación de token Supabase, perfil activo, roles no revocados, permisos
básicos, JWT propagado para RLS, validación de entradas, paginación y errores externos
sanitizados. Las pruebas de API usan servicios simulados y las de aislamiento,
PostgreSQL embebido. La base de pertenencia a clientes está aplicada en desarrollo:
se verificaron RLS y privilegios remotos de las 18 tablas de identidad y cotizador y el asesor de seguridad
quedó sin hallazgos. Falta probar el flujo completo con Auth real y configurar su alta
por invitación; esta revisión no certifica la seguridad del sistema completo.

WAF/DDoS, límites distribuidos, MFA configurado, análisis de archivos, aislamiento de
trabajos, protecciones del agente, alertas y pruebas de recuperación todavía no están
implementados ni desplegados. No se realizaron pruebas de penetración.

Referencias: [OWASP API Security](https://api-security.owasp.org/editions/2023/en/0x11-t10/),
[consumo sin límites](https://api-security.owasp.org/editions/2023/en/0xa4-unrestricted-resource-consumption/),
[prompt injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/) y
[exceso de autonomía](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/).
