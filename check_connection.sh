#!/bin/bash

# Esperar 1 minuto al inicio
sleep 60

# Función para obtener el gateway por defecto
get_gateway() {
    ip route | grep default | awk '{print $3}' | head -n 1
}

# Función para encender LED verde (conexión OK) y apagar rojo
led_green_on() {
    echo none > /sys/class/leds/ACT/trigger 2>/dev/null
    echo 1 > /sys/class/leds/ACT/brightness 2>/dev/null
    echo none > /sys/class/leds/PWR/trigger 2>/dev/null
    echo 0 > /sys/class/leds/PWR/brightness 2>/dev/null
}

# Función para encender LED rojo (sin conexión) y apagar verde
led_red_on() {
    echo none > /sys/class/leds/ACT/trigger 2>/dev/null
    echo 0 > /sys/class/leds/ACT/brightness 2>/dev/null
    echo none > /sys/class/leds/PWR/trigger 2>/dev/null
    echo 1 > /sys/class/leds/PWR/brightness 2>/dev/null
}

# Bucle principal
while true; do
    gateway=$(get_gateway)
    
    if [ -z "$gateway" ]; then
        # No hay gateway - encender LED rojo
        led_red_on
        echo "[$(date)] No hay gateway - reiniciando..."
        sleep 5
        sudo reboot
    elif ping -c 3 -W 5 "$gateway" > /dev/null 2>&1; then
        # Hay conexión - encender LED verde
        led_green_on
        echo "[$(date)] Conectado exitosamente"
    else
        # No hay conexión al gateway - encender LED rojo
        led_red_on
        echo "[$(date)] Sin conexión - reiniciando..."
        sleep 5
        sudo reboot
    fi
    
    # Esperar 2 minutos
    sleep 120
done
