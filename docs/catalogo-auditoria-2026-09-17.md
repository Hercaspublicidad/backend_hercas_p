# Auditoría del catálogo Hercas — 17 de septiembre de 2026

Se releyeron los originales clave de `D:/HERCAS/Cotizaciones productos` y se contrastaron
con el consolidado del 5 de septiembre y el catálogo del piloto Next.js. El registro
de fuentes inventaría 65 libros (18 XLSX y 47 XLS), con hojas, dimensiones y SHA-256.
Se analizaron contenidos de maestro, configuración, listas de materiales, historia
de ventas, materiales y control semanal. No se recalcularon las fórmulas de los 47
cotizadores heredados ni se ejecutaron textos Python de celdas.

## Resultado y alcance comercial

El maestro tiene 205 IDs externos únicos. El consolidado anterior conserva exactamente
esos 205 IDs y nombres: no había pérdida de filas dentro de esa fuente. Sin embargo,
la configuración añade `__export__.product_template_26279_8ab4d27b`, SOUVENIRS_UND,
con seis atributos y cuatro listas de materiales, omitido del consolidado.

El registro unificado contiene **206 referencias**, no 206 productos listos para
publicarse. Se proponen **204 referencias candidatas comerciales** y dos registros
internos. MANUAL es un mecanismo de excepción; RECARGA TARJETA CIVICA pertenece a
Materia Prima / Terceros y requiere confirmar si tiene algún uso de reventa antes
de incorporarlo al catálogo público.

| Grupo propuesto | Referencias | Serie de nombres propuesta |
| --- | ---: | --- |
| Alquiler y pauta exterior | 94 | Hercas Panorama |
| Estructuras publicitarias | 47 | Hercas Forma |
| Aplicaciones de transporte UT | 24 | Hercas Trayecto |
| Servicios técnicos | 13 | Hercas Servicio |
| Impresión en lona | 7 | Hercas Impacto |
| Avisos en sustrato | 6 | Hercas Presencia |
| Señalización | 6 | Hercas Guía |
| Vinilos y corte | 4 | Hercas Adhiere |
| Tecnología LED | 1 | Hercas Luz |
| Impresos litográficos | 1 | Hercas Trazo |
| Promocionales | 1 | Hercas Recuerdo |
| Registros internos | 2 | Hercas Interno |
| **Total** | **206** | |

Las series son propuestas de presentación, no denominaciones oficiales de Odoo.
La estructura comercial recomendada es **grupo → familia → referencia → opciones**;
los activos físicos se vinculan por separado. El archivo conserva 27 combinaciones
grupo/familia, incluyendo el bloque interno. No se crearán 206 páginas ni formularios
independientes solo porque existan 206 referencias técnicas.

## Identificadores asignados

- `external_id`: se conserva el ID externo de Odoo sin modificarlo.
- `id_catalog`: alias estable `HRC-P-022431`, basado en el identificador de plantilla
  representado por el ID externo, independiente del nombre o la agrupación.
- `uuid`: UUID determinista por ID externo, listo para una importación revisada.
- `reference`: se conserva el código existente, por ejemplo PAM-004B.
- `asset_id`: `HRC-A-PAM-004B`, identificador independiente para la ubicación física.

Los identificadores numéricos de 192 referencias se verifican en el archivo de
configuración. Los de las 14 restantes se derivan del ID externo y están señalados
para verificación contra Odoo. El alias y UUID se asignaron en el registro entregado;
no se insertaron productos, activos ni tarifas en Supabase ni se renombró Odoo.

## Correcciones de agrupación

1. **28 VALLA CERCHA:** 14 estaban en Lonas y textiles y 14 en Impresión y vinilos.
   Se proponen en Estructuras publicitarias / Vallas de cercha. La estructura es
   el producto; el revestimiento y su inclusión son características de configuración.
2. **93 ubicaciones y un paquete:** los 94 puntos publicitarios no representan
   94 activos. PAQUETE DE VALLAS requiere composición propia. El catálogo Next.js
   contiene precisamente estas 94 referencias, con los mismos IDs; es un piloto
   de vallas y no todo el catálogo de la empresa.
3. **Souvenirs:** incorporado al registro para no perder la referencia adicional.
4. **Pantalla LED y estructura LED:** no son lo mismo. Pantalla necesita definición
   de modalidad comercial; su nombre no demuestra que corresponda al circuito
   publicitario programático. La estructura se agrupa en fabricación.
5. **Registros similares no fusionados:** se compararon configuraciones de los pares
   22457/22468, 22605/22639 y 22607/22656. Tienen diferencias de atributos/opciones.
   En concreto, las vallas sin fototelón/sin fotovinilo difieren en sustrato, calibre
   y templado. Arcos/dominación de arcos y contrahuellas/dominación de contrahuellas
   también presentan diferencias. No se deduplican por semejanza del nombre.
6. **344 materiales:** permanecen fuera del catálogo comercial. Sus 343 costos
   positivos sirven al motor técnico, no como tarifa de venta.

## Precios y configuración

- Las 205 celdas de precio de venta y de costo del maestro están vacías.
- Configuración contiene 192 plantillas y 7.488 filas de atributos/valores. No es
  un listado de 7.488 variantes `product.product` ni autoriza generar ese número de SKU.
- El historial tiene 5.151 líneas de producto; otras filas describen relaciones y
  no se cuentan como nuevas ventas. El corte real va del 15/04 al 03/09/2026.
- 81 referencias del maestro tienen precios históricos útiles en pedidos de venta:
  importe neto superior a 1 y descuento válido. Mínimo, mediana y máximo son referencias
  de trabajos potencialmente distintos, no una tarifa homogénea por m² o por mes.
- El cruce histórico usa nombre normalizado y solo elimina el prefijo `[código]`
  cuando código y nombre coinciden con el maestro. No se hizo emparejamiento difuso.
  RVN-501 tiene una discrepancia de escritura y queda por conciliar; Anticipo es
  un concepto financiero, no una alta automática de producto.
- El historial no trae moneda ni unidad por línea. El maestro usa Unidades, también
  para ubicaciones. Deben confirmarse moneda y unidad comercial antes de importar
  tarifas a una tabla que actualmente exige COP.
- Hay 581 líneas MANUAL, 146 de ellas en pedidos de venta. Son evidencia de trabajos
  por revisar, no 581 productos nuevos ni autorización para publicar casos especiales.

## Conciliación de vallas

El maestro identifica 93 ubicaciones. La hoja semanal del 30/08 al 05/09/2026
identifica 104 códigos. Coinciden 84: hay 9 solo en maestro y 20 solo en semanal.
El registro de conciliación tiene 113 códigos en total, sin afirmar que todos
estén activos, disponibles o sean propiedad de Hercas.

Hay siete diferencias entre las columnas L y V: CHIG-002, CHIG-003, DMT-001,
PRC-007, PUV-025B, PUV-031 y PUV-084A. Algunas alternativas son cero. PAA-005B
contiene un error `#N/A` en L9. Ninguna de estas alternativas se eligió como tarifa.
El estado semanal es histórico; no se trasladó al calendario operativo actual.

## Consecuencia para Python, Supabase y Next.js

La arquitectura acordada se conserva. Antes de ofrecer cotización automática del
portafolio configurable hacen falta atributos/opciones por referencia, versiones
de formularios y reglas de costo/precio, unidades y parámetros, y mapeos verificables
con Odoo. La tabla actual de precios simples por producto cubre tarifas fijas, pero
no representa por sí sola todas las combinaciones de fabricación.

Para alquiler, separar referencia cotizable, activo físico y paquete. Para
fabricación, usar medidas/material/acabado sin imponer calendario de ocupación.
El administrador de precios valida las tarifas y reglas; su identidad personal
no debe quedar codificada en el motor.

## Entregables y controles

- `outputs/catalogo-20260917/Catalogo Hercas revisado.xlsx`: resumen, 206 referencias
  con IDs/nombres, 113 códigos de valla y hallazgos.
- `outputs/catalogo-20260917/catalogo-auditado.json`: registro reproducible con fuentes,
  filas, métricas y huellas de los originales.
- Scripts en `tools/catalog-audit`: extracción de solo lectura y constructor del libro.

Se comprobaron unicidad de ID externo, alias, UUID y nombre propuesto; suma de grupos,
coincidencia de IDs anteriores, rangos del consolidado y archivo Excel exportado.
Se recalcularon las fórmulas del resumen y se inspeccionaron visualmente las cuatro
hojas. La aprobación de publicación, las tarifas y los casos por conciliar siguen
siendo decisiones pendientes y visibles en el catálogo.
