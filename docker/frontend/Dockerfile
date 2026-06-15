# ============================================================
# Dockerfile del frontend (HTML/CSS/JS estático del Inventario ITU).
# Empaqueta el sitio en una imagen nginx liviana para Docker/Kubernetes.
#
# IMPORTANTE: este Dockerfile espera que, en el contexto de build, además
# del contenido del repo "Proyecto-Inventario-EGI-frontend" (index.html,
# css/, js/, img/, *.html) también estén presentes, en la misma carpeta:
#   - nginx.conf      (de esta carpeta docker/frontend/)
#   - .dockerignore   (de esta carpeta docker/frontend/)
#
# El pipeline de GitHub Actions (.github/workflows/deploy.yml) copia esos
# dos archivos dentro del checkout del repo del frontend antes de buildear.
#
# Build manual de ejemplo:
#   cp docker/frontend/nginx.conf docker/frontend/.dockerignore <ruta-frontend>/
#   docker build -f docker/frontend/Dockerfile -t inventario-web <ruta-frontend>
# ============================================================

FROM nginx:1.25-alpine

# Configuración propia: SPA estática + proxy opcional hacia la API.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia todo el contenido estático del frontend (index.html, css/, js/, img/, *.html).
# El .dockerignore evita copiar Dockerfile/nginx.conf/.git al sitio servido.
COPY . /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
