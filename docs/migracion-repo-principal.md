# Migración del runner al repo principal

Paso a paso para mover el workflow de CI/CD desde el fork personal
`MartinZ18/Proyecto-Inventario-EGI-infraestructura` al repo compartido
del equipo `Agus-tina/Proyecto-Inventario-EGI`.

---

## Contexto

| Elemento | Estado actual | Objetivo |
|---|---|---|
| Código de infra | `MartinZ18/Proyecto-Inventario-EGI-infraestructura` | Ramas `seguridad` y `despliegue` en `Agus-tina/Proyecto-Inventario-EGI` |
| Runner self-hosted | Registrado en el fork de Martin | Registrado en `Agus-tina/Proyecto-Inventario-EGI` |
| GitHub Secrets | En el fork de Martin | En `Agus-tina/Proyecto-Inventario-EGI` |
| Disparar workflow | Solo Martin puede verlo | Cualquier miembro del equipo puede dispararlo |

---

## Requisitos previos

- Tener permisos de **Admin** (Settings) en `Agus-tina/Proyecto-Inventario-EGI`.
- Acceso SSH o sesión activa en la VM **LubuntuEGI** (192.168.56.30).
- El runner actual funcionando (Fases 0-6 del runbook completadas).

---

## Parte 1 — Pushear el código de infraestructura al repo principal

Estas operaciones las hace **Martin** desde su PC o desde LubuntuEGI.
No hace falta que los archivos de seguridad sensibles (credenciales,
tokens) estén incluidos — ya están en `.gitignore`.

```bash
# Clonar el repo principal (si aún no lo tenés clonado)
git clone https://github.com/Agus-tina/Proyecto-Inventario-EGI.git
cd Proyecto-Inventario-EGI
```

### Rama `seguridad` (Martin)

```bash
git checkout -b seguridad

# Copiar solo los directorios que le corresponden a seguridad
# (ajustar rutas si el fork está en otro directorio)
cp -r /ruta/fork/MartinZ18/active-directory   ./active-directory
cp -r /ruta/fork/MartinZ18/pfsense            ./pfsense
cp -r /ruta/fork/MartinZ18/iptables           ./iptables

# Copiar documentación relevante
cp /ruta/fork/MartinZ18/docs/topologia-red.md      ./docs/
cp /ruta/fork/MartinZ18/docs/arquitectura.md        ./docs/
cp /ruta/fork/MartinZ18/docs/auditoria-exigencias.md ./docs/

git add active-directory/ pfsense/ iptables/ docs/
git commit -m "feat: agregar configuración de seguridad perimetral y documentación"
git push origin seguridad
```

### Rama `despliegue` (integrante de despliegue, o Martin si no hay otro)

```bash
git checkout -b despliegue

cp -r /ruta/fork/MartinZ18/kubernetes         ./kubernetes
cp -r /ruta/fork/MartinZ18/docker             ./docker
cp -r /ruta/fork/MartinZ18/infra              ./infra
cp -r /ruta/fork/MartinZ18/.github            ./.github

# Documentación de despliegue
cp /ruta/fork/MartinZ18/docs/runbook-despliegue.md     ./docs/
cp /ruta/fork/MartinZ18/docs/bitacora-despliegue.md    ./docs/
cp /ruta/fork/MartinZ18/docs/migracion-repo-principal.md ./docs/

# Archivos raíz
cp /ruta/fork/MartinZ18/.gitignore ./

git add kubernetes/ docker/ infra/ .github/ docs/ .gitignore
git commit -m "feat: agregar manifiestos de Kubernetes, workflow CI/CD y runbook"
git push origin despliegue
```

> Los archivos `infra/red.local.env` e `infra/secretos.local.md` están
> en `.gitignore` y NO deben commitearse.

---

## Parte 2 — Configurar GitHub Secrets en el repo principal

Ir a `https://github.com/Agus-tina/Proyecto-Inventario-EGI` →
**Settings → Secrets and variables → Actions → New repository secret**.

Cargar estos 7 secretos (obtener los valores de `infra/secretos.local.md`
o de `apuntes.txt`):

| Nombre | Descripción |
|---|---|
| `REPO_ACCESS_TOKEN` | PAT con permiso `repo` para clonar el backend y el frontend |
| `JWT_SECRET` | Clave secreta para firmar los JWT (mínimo 32 bytes aleatorios) |
| `SQLSERVER_USER` | Usuario de SQL Server (`inventario_app`) |
| `SQLSERVER_PASSWORD` | Password del usuario SQL |
| `MONGO_ROOT_USER` | Usuario root de MongoDB |
| `MONGO_ROOT_PASSWORD` | Password root de MongoDB |
| `LDAP_BIND_PASSWORD` | Password del usuario de servicio LDAP (`svc-inventario`) — **nuevo**, no estaba en el fork original |

> Si `REPO_ACCESS_TOKEN` ya tiene acceso al repo principal (mismo
> propietario), no hace falta cambiarlo. El token que estaba en el fork
> sirve si tiene permisos sobre `Agus-tina/Proyecto-Inventario-EGI`.

---

## Parte 3 — Dar de baja el runner actual

Desde la interfaz web del fork: `https://github.com/MartinZ18/Proyecto-Inventario-EGI-infraestructura` →
**Settings → Actions → Runners** → seleccionar `lubuntuegi-minikube` →
**"Remove runner"** → copiar el token de remoción que aparece.

En LubuntuEGI:

```bash
cd ~/actions-runner

# Detener e desinstalar el servicio systemd
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# Desregistrar el runner (usa el token de remoción de la web)
./config.sh remove --token <TOKEN_DE_REMOCION>
```

> Si el fork ya no está accesible o el token expiró, se puede omitir
> el `./config.sh remove` — el runner quedará en estado "Offline" en
> la web del fork, pero no afecta al nuevo registro.

---

## Parte 4 — Registrar el runner en el repo principal

En el repo principal: `https://github.com/Agus-tina/Proyecto-Inventario-EGI` →
**Settings → Actions → Runners → New self-hosted runner** → elegir
**Linux** → copiar el token de la sección "Configure".

En LubuntuEGI (el directorio `~/actions-runner` ya existe de la
instalación anterior — no hay que volver a descargar los binarios):

```bash
cd ~/actions-runner

# Registrar contra el repo principal
./config.sh \
  --unattended \
  --url https://github.com/Agus-tina/Proyecto-Inventario-EGI \
  --token <TOKEN_DE_REGISTRO_NUEVO> \
  --labels minikube \
  --name lubuntuegi-minikube

# Instalar y arrancar como servicio systemd
sudo ./svc.sh install
sudo ./svc.sh start

# Verificar
sudo ./svc.sh status
```

Verificar en la web que el runner aparece en estado **"Idle"** (verde)
en `https://github.com/Agus-tina/Proyecto-Inventario-EGI/settings/actions/runners`.

---

## Parte 5 — Crear `infra/red.local.env` en el workspace del runner

El workflow lee `infra/red.local.env` en el paso "Resolver configuración
de red". El runner crea un nuevo directorio de checkout en
`~/actions-runner/_work/Proyecto-Inventario-EGI/Proyecto-Inventario-EGI/`.
Hay que asegurarse de que `red.local.env` exista ahí después del primer
checkout.

La forma más sencilla es crear un symlink al archivo existente:

```bash
# Esperar a que el primer checkout se haga (disparar el workflow una vez
# o esperar al primer push a la rama despliegue)
ln -s ~/inventario-red.local.env \
  ~/actions-runner/_work/Proyecto-Inventario-EGI/Proyecto-Inventario-EGI/infra/red.local.env
```

O bien copiar el archivo directamente:

```bash
cp ~/infra/red.local.env \
  ~/actions-runner/_work/Proyecto-Inventario-EGI/Proyecto-Inventario-EGI/infra/red.local.env
```

> **Importante:** el path del workspace cambia si el runner se registra
> en un repo con nombre distinto. La ruta sigue el patrón:
> `~/actions-runner/_work/<nombre-repo>/<nombre-repo>/`.
> En este caso: `_work/Proyecto-Inventario-EGI/Proyecto-Inventario-EGI/`.

---

## Parte 6 — Verificar

1. Ir a `https://github.com/Agus-tina/Proyecto-Inventario-EGI` →
   **Actions → Deploy Inventario ITU a Minikube → Run workflow**.
2. Seleccionar la rama `despliegue` y ejecutar.
3. Esperar a que terminen todos los pasos (≈ 3-5 min).
4. Desde LubuntuEGI confirmar:

```bash
kubectl get pods -n inventario
# Los 3 pods deben estar en Running (1/1)

curl http://192.168.56.30:30080/
# Debe responder 200

# Verificar que MongoDB tiene los 12 documentos
kubectl exec -n inventario deploy/mongo -- \
  mongosh --quiet -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval 'db = db.getSiblingDB("inventario_componentes"); printjson(db.computadoras.countDocuments({}))'
# Debe imprimir 12
```

5. Probar el login desde el navegador con `mgomez` (sin `@itu.local`).

---

## Parte 7 — (Opcional) Marcar el fork como archivado

Una vez que el workflow corre correctamente desde el repo principal, el
fork `MartinZ18/Proyecto-Inventario-EGI-infraestructura` queda obsoleto.

Para archivarlo sin borrar el historial:
`https://github.com/MartinZ18/Proyecto-Inventario-EGI-infraestructura` →
**Settings → Danger Zone → Archive this repository**.

---

## Resumen rápido

```
1. git push seguridad   → Agus-tina/Proyecto-Inventario-EGI
2. git push despliegue  → Agus-tina/Proyecto-Inventario-EGI
3. Cargar 7 Secrets en el repo principal
4. En LubuntuEGI: sudo ./svc.sh stop && sudo ./svc.sh uninstall && ./config.sh remove
5. En LubuntuEGI: ./config.sh --url <repo-principal> --token <nuevo> ...
6. sudo ./svc.sh install && sudo ./svc.sh start
7. Crear infra/red.local.env en el workspace del runner
8. Disparar el workflow y verificar pods + login
```
