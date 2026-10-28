FROM node:18-alpine

WORKDIR /app

# Copiar archivos de dependencias
COPY package*.json ./

# Instalar dependencias de producción
RUN npm ci --only=production

# Copiar código fuente
COPY . .

# Crear carpeta para la base de datos de producción si no existe
RUN mkdir -p /app/data

ENV NODE_ENV=production
ENV PORT=3010
ENV DB_PATH=/app/data/filtros_panasa.db

EXPOSE 3010

CMD ["node", "server.js"]
