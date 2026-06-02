#!/bin/bash

# Script de instalación para el monitor de conexión
# Descarga el script y lo configura para ejecutar al inicio con crontab

SCRIPT_URL="https://raw.githubusercontent.com/b-lod-riglesias/multi-scripts/main/script-conexion/check_connection.sh"
SCRIPT_PATH="/usr/local/bin/check_connection.sh"

echo "Descargando script..."
curl -sL "$SCRIPT_URL" -o "$SCRIPT_PATH"

echo "Dando permisos de ejecución..."
chmod +x "$SCRIPT_PATH"

echo "Añadiendo al crontab para ejecutar al inicio..."
(crontab -l 2>/dev/null; echo "@reboot sleep 60 && $SCRIPT_PATH &") | crontab -

echo "Verificando crontab..."
crontab -l | grep check_connection

echo ""
echo "Instalación completada!"
echo "El script se ejecutará automáticamente en el próximo reinicio."
echo ""
echo "Para ejecutar manualmente ahora:"
echo "  sudo $SCRIPT_PATH &"
echo ""
echo "Para ver el log del script, revisa la salida por stdout."
