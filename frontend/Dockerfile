FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html dashboard.html styles.css main.js cube.js /usr/share/nginx/html/

# Build-time version, served at /version.txt and shown in the footer.
ARG VERSION=dev
RUN echo "$VERSION" > /usr/share/nginx/html/version.txt

EXPOSE 80
