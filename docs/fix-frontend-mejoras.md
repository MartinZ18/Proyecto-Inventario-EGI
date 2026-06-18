# Mejoras y fixes pendientes en el frontend

Repo: `Agus-tina/Proyecto-Inventario-EGI`, rama `frontend`
Revisión: 2026-06-18

---

## 🔴 Bugs críticos

### 1. Botón "Cerrar Sesión" no funciona en `detalle.html`

El botón no tiene `id` ni event listener. El usuario queda atrapado en
el detalle sin poder cerrar sesión.

**`detalle.html` — agregar `id="btnCerrarSesion"` al botón:**

```html
<!-- antes: -->
<a class="btn btn-outline-light fw-semibold cerrar-sesion">

<!-- después: -->
<a id="btnCerrarSesion" class="btn btn-outline-light fw-semibold cerrar-sesion">
```

**`js/detalle.js` — agregar el listener (ya existe `logout` en los imports):**

```js
document.getElementById('btnCerrarSesion')?.addEventListener('click', () => {
    logout();
    window.location.href = 'index.html';
});
```

---

### 2. Mesa muestra `null` en la tabla del listado

Cuando el equipo tiene `mesa = null`, la celda muestra el texto
`"null"` en vez de un guion.

**`js/listado.js` — en la función `dibujarTabla()`, cambiar:**

```js
// antes:
<td>${item.equipo.mesa}</td>

// después:
<td>${item.equipo.mesa ?? '-'}</td>
```

---

### 3. Breadcrumb "Inicio" lleva al login en lugar del listado

En `detalle.html`, el breadcrumb tiene `href="index.html"` que es el
login. Dentro de la app, "Inicio" debería volver al listado.

**`detalle.html`:**

```html
<!-- antes: -->
<li class="breadcrumb-item"><a href="index.html" class="text-info p-2">Inicio</a>

<!-- después: -->
<li class="breadcrumb-item"><a href="listado.html" class="text-info p-2">Listado</a>
```

---

## 🟡 Funcionalidades faltantes

### 4. Campo `mesa` no se muestra en el detalle del equipo

`detalle.html` tiene la card de Ubicación pero no tiene el campo Mesa,
aunque ya existe en SQL y el formulario ya lo edita.

**`detalle.html` — agregar dentro de la card Ubicación, después de "Edificio/Piso":**

```html
<div class="col-6">
    <p class="text-muted small mb-0">Mesa</p>
    <p class="fw-bold" id="detMesa">—</p>
</div>
```

**`js/detalle.js` — agregar la línea en `cargarDetalle()`:**

```js
// agregar junto a las otras líneas de SQL data:
document.getElementById('detMesa').textContent = equipo.mesa ?? '-';
```

---

### 5. Campo `bateria.estado` no existe — muestra siempre `—`

En la vista de detalle de una laptop, `detBatEstado` intenta mostrar
`comp.bateria?.estado` pero los datos de MongoDB no tienen ese campo.
Tienen `capacidad_mah` y `ciclos`. La sección de batería muestra `—`
siempre.

**`js/detalle.js` — cambiar:**

```js
// antes:
document.getElementById('detBatEstado').textContent = comp.bateria?.estado ?? '-';
document.getElementById('detBatCiclos').textContent = comp.bateria?.ciclos ?? '-';

// después:
document.getElementById('detBatEstado').textContent =
    comp.bateria?.capacidad_mah ? `${comp.bateria.capacidad_mah} mAh` : '-';
document.getElementById('detBatCiclos').textContent = comp.bateria?.ciclos ?? '-';
```

**`detalle.html` — cambiar la etiqueta del campo:**

```html
<!-- antes: -->
<p class="text-muted small mb-0">Estado</p>

<!-- después: -->
<p class="text-muted small mb-0">Capacidad</p>
```

---

### 6. No hay indicador visual del estado del equipo en el listado

Un equipo `EN_REPARACION` o `BAJA` se ve igual a uno `OPERATIVO` en la
tabla. Sería útil agregar una columna Estado con badges de color.

**`listado.html` — agregar columna en el `<thead>`:**

```html
<th class="fw-normal py-3 text-center">Estado</th>
```

**`js/listado.js` — en `dibujarTabla()`, agregar celda en cada fila:**

```js
const estadoBadge = {
    'OPERATIVO':     '<span class="badge bg-success">Operativo</span>',
    'EN_REPARACION': '<span class="badge bg-warning text-dark">En reparación</span>',
    'BAJA':          '<span class="badge bg-danger">Baja</span>',
};
const badge = estadoBadge[item.equipo.estado] ?? `<span class="badge bg-secondary">${item.equipo.estado ?? '-'}</span>`;

// agregar en el innerHTML de la fila:
<td>${badge}</td>
```

---

### 7. Agregar `obtenerPersonas()` en `api.js`

Cuando el backend agregue `GET /personas/`, el frontend necesita esta
función para cargar el dropdown de "Responsable asignado" en el
formulario.

**`js/api.js` — agregar al final:**

```js
export async function obtenerPersonas() {
    return await fetchWithAuth('/inventario/personas', { method: 'GET' });
}
```

---

### 8. Botón Eliminar visible para no-técnicos en el listado

El botón Eliminar se renderiza para todos los roles y solo se bloquea
con `alert()` al hacer click. Mejor no mostrarlo si el rol no es
Técnico, igual que el botón "Nueva Máquina".

**`js/listado.js` — en `dibujarTabla()`, condicionar el botón:**

```js
// reemplazar la celda de eliminar por:
<td>
    ${rol === 'Tecnicos'
        ? `<button class="btn btn-danger btn-sm" onclick="eliminarEquipoTabla(${item.equipo.id_equipo})">Eliminar</button>`
        : '-'}
</td>
```

---

## 🔵 Pulido general

### 9. Idioma incorrecto en todos los HTML

Todos los archivos tienen `<html lang="en">`. La app está en español.

**Cambiar en `index.html`, `listado.html`, `detalle.html`, `formulario.html`:**

```html
<!-- antes: -->
<html lang="en">

<!-- después: -->
<html lang="es">
```

---

### 10. Títulos de página genéricos

Los `<title>` son "Página Login", "Página listado", etc.

| Archivo | Cambiar a |
|---|---|
| `index.html` | `Inventario ITU — Ingresar` |
| `listado.html` | `Inventario ITU — Listado` |
| `detalle.html` | `Inventario ITU — Detalle` |
| `formulario.html` | `Inventario ITU — Nueva máquina` |

---

## Resumen de prioridades

| # | Archivo/s | Tipo | Impacto |
|---|---|---|---|
| 1 | `detalle.html` + `detalle.js` | Bug | No se puede cerrar sesión desde el detalle |
| 2 | `listado.js` | Bug | Mesa muestra "null" en vez de "-" |
| 3 | `detalle.html` | Bug | Breadcrumb lleva al login |
| 4 | `detalle.html` + `detalle.js` | Feature | Mesa no aparece en el detalle |
| 5 | `detalle.html` + `detalle.js` | Feature | Capacidad batería siempre en "-" |
| 6 | `listado.html` + `listado.js` | Feature | Sin indicador de estado en la tabla |
| 7 | `api.js` | Feature | Falta `obtenerPersonas()` para el dropdown |
| 8 | `listado.js` | UX | Botón Eliminar visible a no-técnicos |
| 9 | todos los HTML | Pulido | `lang="en"` → `lang="es"` |
| 10 | todos los HTML | Pulido | Títulos genéricos |
