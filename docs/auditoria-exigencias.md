# Auditoría de exigencias del proyecto

Basada en el documento "Proyecto Integrador EGI: Ecosistema de Inventario Seguro".
Fecha de revisión: 2026-06-18.

---

## Contexto / problema

| Requisito | Estado | Notas |
|---|---|---|
| Sistema centralizado de inventario de computadoras | ✅ | Cubre todo el ciclo: ubicación + componentes |
| SQL Server para ubicación, responsable, fechas | ✅ | `inventario_ubicaciones`: tablas Equipo, Ubicacion, Persona, Asignacion, Mantenimiento |
| MongoDB para componentes de hardware | ✅ | `inventario_componentes.computadoras`, 12 docs con estructura variada (CPU, RAM, storage, SO, periféricos) |
| Autenticación contra Active Directory/LDAP | ✅ | FastAPI + ldap3, JWT 60 min, roles Tecnicos/Docentes/Alumnos |
| Seguridad perimetral con pfSense | ✅ | NAT port-forward WAN:80 → NodePort 30080 + auth pfAdmins contra AD |
| Versionado en Git con evolución visible | ✅ | Repo infraestructura + ramas backend/frontend/bases-de-datos en el repo principal |

---

## Arquitectura requerida (5 componentes)

| Componente | Estado |
|---|---|
| Frontend (`inventario-web`) | ✅ nginx + Bootstrap, NodePort 30080 |
| MongoDB (`inventario-db`) | ✅ Pod en namespace `inventario`, colección `computadoras` |
| SQL Server (`ubicacion-db`) | ✅ VM externa 192.168.56.20, acceso por Endpoints K8s |
| Servidor LDAP/AD | ✅ DC01-ITU 192.168.56.10, Endpoints K8s `ldap-service` |
| Firewall perimetral (pfSense) | ✅ pfSense-Gateway-B1 192.168.56.2, NAT + auth AD |

---

## Desafíos técnicos (objetivos)

| Objetivo | Estado | Detalle |
|---|---|---|
| Conectividad interna (puertos, env vars, selectors) | ✅ | ConfigMap + Secret + Endpoints externos para SQL y LDAP |
| Acceso externo seguro simulando NAT de pfSense | ✅ | pfSense: WAN:80 → 30080; VirtualBox: host:80 → WAN:80 |
| Zero-trust con NetworkPolicies | ✅ | 7 políticas Calico (00-06), default-deny, menor privilegio |
| DBs solo aceptan conexiones del backend | ✅ | Policy 04 (backend ← frontend) + 06 (mongo ← backend) |
| MongoDB: crear colección con documentos variados | ✅ | 12 docs: desktops, laptops, 1 servidor, 1 baja; estructuras distintas (batería, pantalla_integrada para laptops; null en desktops) |
| MongoDB: búsquedas filtradas | ✅ | Frontend filtra por tipo y ubicación; backend GET `/inventario/{id}` |
| MongoDB: actualizar registros | ✅ | `PUT /inventario/componentes/{id}` + `actualizarComponentes()` en formulario.js |
| MongoDB: eliminar datos | ✅ | `DELETE /inventario/componentes/{id}` + `eliminarEquipo()` en listado.js y detalle.js |
| MongoDB accesible por línea de comando (shell) | ✅ | `kubectl exec` + `mongosh` funcional, verificado |
| AD recibe tráfico de autenticación del frontend | ✅ | Policy 05 permite egress backend → ipBlock `192.168.56.0/24` :389 |
| Bloquear tráfico no autorizado en el namespace | ✅ | Policy 00 default-deny como base |
| Minikube con CNI compatible para NetworkPolicies | ✅ | `--cni=calico` en el start |

---

## Entregables

| Entregable | Estado | Notas |
|---|---|---|
| Documentación del proyecto | ✅ | docs/arquitectura.md, topologia-red.md, runbook, bitácoras |
| Esquema arquitectura (servicios, puertos, reglas de red) | ✅ | docs/arquitectura.md con diagrama Mermaid y matriz de puertos |
| Esquema de BD (diseño previo + scripts + JSON) | ⚠️ Parcial | Scripts SQL y JSON con 12 docs OK. Falta E-R o diagrama de diseño previo visible en el repo principal |
| Flujograma de la aplicación web | ❌ Falta | No existe diagrama de flujo de navegación UX (login → listado → detalle → formulario) |
| Repositorio Git con todo el código | ✅ | Infraestructura + backend + frontend + bases-de-datos en repo principal |
| Scripts de creación de BD + JSON de documentos | ✅ | `sql-server-iis/scripts/` + `database/scripts/inventario-db_mongo.js` |
| Manifiestos de Kubernetes | ✅ | `kubernetes/` completo: deployments, services, configmaps, secrets, network-policies, namespace |
| Ecosistema funcional en Minikube | ✅ | Verificado 2026-06-18: login OK, 12 equipos en listado, detalle completo, CRUD funcional |
| Aplicación web gestión de inventario | ⚠️ Casi completa | CRUD ✅, filtros ✅, detalle ✅ — "Responsable asignado" en formulario no carga personas (falta endpoint `/personas/` en backend) |
| Presentación formato PowerPoint | ❌ Falta | No creada |

---

## Pendientes para la defensa

### 1. Flujograma de la aplicación (❌ obligatorio)

No existe ningún archivo que lo documente. Hay que dibujar el flujo de
navegación entre páginas:

```
login (index.html)
  └─► listado.html  ← filtros por tipo y ubicación
        ├─► detalle.html?id=N  ← solo lectura para Docentes/Alumnos
        │     ├─► formulario.html?id=N  (editar, solo Tecnicos)
        │     └─► eliminar (modal confirmación, solo Tecnicos)
        └─► formulario.html  (nuevo equipo, solo Tecnicos)
```

Se puede hacer en Draw.io, Lucidchart o como diagrama Mermaid.
Responsable sugerido: integrante de Frontend.

### 2. Diagrama E-R o esquema de diseño de BD (⚠️ verificar con el equipo)

Los scripts de creación existen (`sql-server-iis/scripts/`) pero el
documento de *diseño previo* (E-R con tablas, relaciones y tipos de dato)
probablemente lo tenga el integrante de bases de datos. Confirmar que
esté en el repo principal antes de la defensa.

### 3. "Responsable asignado" en el formulario (⚠️ visible en demo)

Las personas **sí están cargadas en SQL** (12 registros: técnicos,
docentes, alumnos, administrador) y se muestran correctamente en la
vista de detalle. El problema es que no existe `GET /personas/` en el
backend, por lo que el formulario de alta/edición no puede listarlas en
el dropdown. El integrante de backend tiene que agregar ese endpoint.

### 4. Presentación PowerPoint (❌ obligatorio)

Entregable obligatorio mencionado explícitamente en las exigencias.
Debe incluir al menos: arquitectura, flujo de autenticación, BD (SQL +
Mongo), NetworkPolicies, demo del ecosistema.
