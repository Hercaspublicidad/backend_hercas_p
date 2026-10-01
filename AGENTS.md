# Coordinación del proyecto Hercas

## Plan compartido oficial

Por instrucción del usuario, mantener actualizado el archivo compartido al trabajar
en el proyecto:

`\\hercascloud\VERIFICACIONES HERCAS\Optimizaciones Hercas\Hercas - Plan de trabajo Anderson y tu.xlsx`

## Levantamiento de requerimientos colaborativo

Por indicación del usuario, el archivo colaborativo de requerimientos se administra
en SharePoint:

`https://hercas1-my.sharepoint.com/personal/asesoria_hercas_net/Documents/Hercas%20-%20Levantamiento%20de%20requerimientos%20corregido.xlsx`

- Usar esta copia para revisar y coordinar requisitos. No sustituirla con la copia
  UNC ni regenerarla desde constructores iniciales.
- Cada vez que se trabaje en el proyecto, actualizar en este libro los requisitos,
  decisiones, bloqueos, evidencias y cierres que se hayan visto afectados antes de
  finalizar la actividad. Conservar los cambios hechos por los colaboradores y no
  marcar un requisito cerrado sin evidencia y validación aplicables.
- El plan de trabajo sigue en la ruta UNC indicada arriba hasta que el usuario
  indique mover también ese archivo a SharePoint.

La carpeta también es conocida por el usuario como `Z:\Optimizaciones Hercas`.
Preferir la ruta UNC, porque Z: puede no estar montada en la sesión de herramientas.

- Este es el plan oficial usado conjuntamente por el usuario y Anderson. Las copias
  de `outputs` son auxiliares y no sustituyen la versión compartida.
- Leer la versión compartida más reciente antes de editar. Conservar avances,
  responsables, decisiones, comentarios, fórmulas y evidencia de ambos usuarios.
- Actualizar los requisitos, decisiones, bloqueos y evidencias afectados por el
  trabajo realizado. No marcar implementación o aprobación por la sola preparación
  de un documento, tabla, pantalla o plan.
- No regenerar el archivo oficial desde los constructores iniciales, porque eso
  puede restablecer estados y borrar acuerdos posteriores. Hacer cambios puntuales.
- Antes de publicar, verificar que la fuente no haya cambiado desde la lectura y
  guardar una copia recuperable. Si cambió, incorporar los cambios sobre una nueva
  lectura; nunca sobrescribirlos silenciosamente.
- Si el archivo está abierto/bloqueado, preparar el cambio local, pedir que ambos
  guarden y cierren, y no forzar el desbloqueo. Informar si la actualización oficial
  quedó pendiente. No reportar una copia local como actualización compartida.
- Leer la habilidad de hojas de cálculo y validar los cambios y fórmulas antes de
  guardar. El acceso UNC puede requerir escalación de permisos del entorno.
- Esta instrucción aplica durante trabajos del proyecto. No implica crear un
  monitor programado, enviar mensajes a Anderson ni operar sistemas por cuenta propia.

## Reparto de trabajo acordado

- Carlos: todo Supabase, incluyendo Auth/MFA, tablas, migraciones, RLS, SQL/RPC,
  Storage, Realtime, configuración e importaciones; también frontend y aceptación.
- Anderson: FastAPI, reglas Python, Odoo, integraciones externas y trabajadores.
- Dos operaciones simultáneas como máximo: una por persona. Acordar contratos
  primero e integrar y aceptar la etapa antes de avanzar.
- Etapa 0 es preparación, diagnóstico y decisiones. SER-011 y SER-014 comienzan
  ejecución desde etapa 1, únicamente con sus prerrequisitos resueltos. Los controles
  transversales se verifican en cada entrega y cierran globalmente en etapa 12.

## Reglas persistentes de rama y ejecución

- Todo cambio de backend se realiza únicamente en esta carpeta y en la rama
  `carlos`. Verificar la rama antes de editar.
- No cambiar de rama, crear ramas, fusionar, hacer `commit` ni `push` salvo una
  instrucción explícita del usuario para esa acción puntual.
- No iniciar, reiniciar ni detener FastAPI, Uvicorn ni otro proceso del backend.
  El usuario maneja los servidores manualmente.
- Para cambios de frontend, trabajar únicamente en
  `D:\Web Hercas\Web\pagina_hercas` y su rama `integraci0n`; no implementar
  frontend en este repositorio ni en worktrees alternos.
