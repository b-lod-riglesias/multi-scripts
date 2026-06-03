# Ollama LAN Installer

Este directorio contiene `install_ollama.sh`, un script de Bash para instalar y configurar **Ollama** en sistemas Debian/Ubuntu con soporte para uso en red local (LAN) y detección/reparación de drivers NVIDIA.

## ¿Qué hace?

1. **Instala Ollama**  
   Descarga e instala Ollama desde el script oficial (`https://ollama.com/install.sh`) si no está presente en el sistema.

2. **Configura el servicio systemd**  
   Crea un *override* en `/etc/systemd/system/ollama.service.d/override.conf` para exponer Ollama en la red local:
   - `OLLAMA_HOST=0.0.0.0:11434` (por defecto).
   - `OLLAMA_SCHED_SPREAD=1` para distribuir la carga entre GPUs.

3. **Gestiona drivers NVIDIA**
   - Detecta GPUs NVIDIA vía PCI.
   - Si `nvidia-smi` no ve todas las tarjetas, instala el driver adecuado:
     - Ramificación **580** para GPUs Pascal (GTX 10xx) o si se fuerza con `--force-nvidia-580`.
     - `cuda-drivers` o `ubuntu-drivers` para hardware más moderno.
   - Marca cuando es necesario reiniciar para cargar el nuevo driver.

4. **Conserva la configuración de red**
   - No toca DNS ni DHCP. Solo verifica que `ollama.com` sea resoluble.

5. **Estado final**
   - Reinicia y habilita el servicio `ollama`.
   - Muestra el estado del servicio, el puerto en escucha y ejemplos de `curl` usando la IP LAN.

## Opciones

```bash
./install_ollama.sh [opciones]
```

| Opción | Descripción |
|--------|-------------|
| `--reboot` | Reinicia automáticamente si se cambió el driver NVIDIA. |
| `--no-spread` | No establece `OLLAMA_SCHED_SPREAD=1`. |
| `--skip-nvidia` | Omite la inspección/instalación de drivers NVIDIA. |
| `--force-nvidia-580` | Fuerza la instalación del driver branch 580. |
| `--host HOST:PORT` | Cambia la dirección de escucha (por defecto `0.0.0.0:11434`). |
| `-h, --help` | Muestra la ayuda completa. |

## Variables de entorno

- `OLLAMA_HOST_VALUE` — Sobrescribe la dirección de bind.
- `OLLAMA_SCHED_SPREAD_VALUE` — Sobrescribe el valor de spread.

## Uso rápido

```bash
sudo ./install_ollama.sh
```

Requiere privilegios de root (re-eleva automáticamente con `sudo` si no se ejecuta como root).

## Instalación directa con curl (copiar y pegar)

Si prefieres ejecutarlo directamente desde GitHub sin clonar el repositorio:

```bash
curl -fsSL https://raw.githubusercontent.com/b-lod-riglesias/multi-scripts/main/ollama/install_ollama.sh | sudo bash
```

> Puedes añadir las opciones al final si las necesitas, por ejemplo:
> ```bash
> curl -fsSL ... | sudo bash -s -- --reboot --host 0.0.0.0:11434
> ```
