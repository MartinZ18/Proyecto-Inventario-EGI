# iptables — Firewall del host de Minikube

## Por qué iptables además de Calico y pfSense

La consigna del Proyecto Integrador pide un firewall a nivel de host
(GUFW o equivalente). Este proyecto usa **iptables directo** en lugar
de GUFW porque GUFW es solo una interfaz gráfica sobre `ufw`, que a su
vez es una capa sobre iptables — y Minikube ya manipula iptables
extensamente (Calico, kube-proxy). Trabajar con `iptables` directo
evita conflictos entre tres capas de abstracción distintas sobre el
mismo subsistema del kernel.

Esto da **tres capas de seguridad de red complementarias**, no
redundantes:

| Capa | Dónde | Qué controla | Archivo(s) |
|---|---|---|---|
| **iptables** | Host Linux de Minikube | Tráfico hacia el **nodo** (SSH, ICMP, NodePort 30080) | `reglas-perimetrales.sh` |
| **Calico NetworkPolicies** | Dentro del clúster | Tráfico **entre pods** (frontend↔backend↔mongo, egress a SQL/AD) | `kubernetes/network-policies/*.yaml` |
| **pfSense** | Borde de la red del laboratorio | Tráfico entre la **WAN del profesor y la LAN interna** (NAT, port-forward) | `pfsense/README.md` |

Un atacante que comprometa, por ejemplo, el pod del frontend, se
encuentra con las NetworkPolicies de Calico (no puede hablarle a Mongo
ni a SQL Server directo). Un escaneo desde la red del laboratorio hacia
el host de Minikube se encuentra con iptables (solo SSH/ICMP/NodePort
permitidos). Y el acceso desde fuera del laboratorio se encuentra con
pfSense (solo el puerto 80 reenviado al NodePort).

---

## Alcance del script `reglas-perimetrales.sh`

El script **solo modifica la cadena `INPUT`** (tráfico destinado al
propio host). Deliberadamente **no toca `FORWARD`** ni las cadenas
`cali-*` / `KUBE-*` que Calico y kube-proxy gestionan dinámicamente:
poner `FORWARD` en `DROP` por defecto rompería el reenvío pod-to-pod,
kube-dns y el NodePort hacia los Services.

Reglas aplicadas (en orden):
1. Loopback → `ACCEPT`.
2. Conexiones `ESTABLISHED,RELATED` → `ACCEPT`.
3. SSH (22/TCP) desde `[IP_RED_PROF]/24` → `ACCEPT`.
4. ICMP echo-request desde `[IP_RED_PROF]/24` → `ACCEPT` (ping de diagnóstico).
5. NodePort del frontend (30080/TCP) desde `[PFSENSE_LAN_IP]` y desde
   `[IP_RED_PROF]/24` → `ACCEPT`.
6. Política por defecto de `INPUT` → `DROP`.

---

## Uso

1. Editar las variables `RED_LABORATORIO`, `PFSENSE_LAN_IP` y
   `NODEPORT_FRONTEND` al inicio de `reglas-perimetrales.sh` con los
   valores reales (ver `docs/topologia-red.md`).
2. Ejecutar como root en el host de Minikube:
   ```bash
   sudo ./reglas-perimetrales.sh
   ```
3. Verificar que SSH y el frontend (`http://[MINIKUBE_IP]:30080`) sigan
   accesibles desde la red del laboratorio, y que un acceso desde un
   origen no permitido sea rechazado (`Connection timed out`).

### Persistencia

Por defecto, las reglas de iptables se pierden al reiniciar. Para
persistirlas (Debian/Ubuntu, distro típica de Minikube):
```bash
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

### Rollback

Si algo queda mal bloqueado y se pierde el acceso SSH, desde la
consola física/virtual de la VM:
```bash
iptables -P INPUT ACCEPT
iptables -F INPUT
```

---

## Checklist de verificación

- [ ] `iptables -L INPUT -v -n` muestra las 5 reglas + política `DROP`.
- [ ] SSH desde la red del laboratorio funciona.
- [ ] SSH desde una IP fuera de `[IP_RED_PROF]/24` es rechazado (probar
      con un host externo o cambiar temporalmente la variable).
- [ ] `http://[MINIKUBE_IP]:30080` responde desde `[PFSENSE_LAN_IP]` y
      desde la red del laboratorio.
- [ ] El clúster sigue funcionando con normalidad (`kubectl get pods -n
      inventario`, pods `Running`, sin reinicios) — confirma que no se
      tocó `FORWARD`.
- [ ] Reglas persistidas con `netfilter-persistent save` (sobreviven a
      un reinicio del host).
