# Reporte de disponibilidades

## Propósito

Katherine, con el rol `availability_manager`, genera desde el módulo de
disponibilidades un Excel compartible para los próximos 45 días. El archivo no
se edita manualmente: se crea desde Supabase en el momento de solicitarlo.

## Datos por valla

Cada fila representa una valla y contiene:

1. Código canónico.
2. Descripción comercial.
3. Ubicación o dirección.
4. Latitud y longitud verificadas.
5. Imagen embebida cuando la referencia de medio sea válida.
6. Precio oficial publicado. Si no hay un precio publicado, el archivo muestra
   `Pendiente de publicar`; no debe usar una observación histórica como tarifa.
7. Estado en la ventana: `Disponible`, `Separada`, `Rentada/comprometida` o
   `Mantenimiento`.
8. Primera fecha disponible entre hoy y hoy + 45 días.

## Seguridad y contrato de integración

- Endpoint previsto: `GET /api/v1/cotizador/reportes/disponibilidades.xlsx`.
- Solo `availability_manager`, `pricing_manager` y `systems_admin` pueden
  generarlo. Los comerciales consultan el calendario, pero no reciben datos de
  precio en la exportación compartida.
- La autenticación llega al backend Python mediante el JWT del usuario. El
  backend consulta Supabase con las políticas y proyecciones necesarias, sin
  enviar secretos al navegador.
- El botón **Compartir** permite a Katherine elegir uno o varios clientes y
  sus direcciones de correo. Cada destinatario genera una entrega auditable con
  periodo, solicitante, fecha, resultado y referencia del archivo. Puede elegir
  cuentas cliente existentes o añadir una dirección puntual válida.
- El envío usa una cola auditable y se ejecuta solo al confirmar el botón de
  compartir, con el proveedor de correo configurado. No hay envíos automáticos.
- No se incluyen cliente, razón de bloqueo, evidencia, identificadores de
  cotización ni otros datos internos de una reserva.

## Datos pendientes antes del primer envío

Al 2026-09-30 faltan coordenadas verificadas, precios publicados y referencias
de imagen en Supabase. La generación debe informar esas ausencias y no marcar
el reporte como completo hasta que recepción y precios las validen.
