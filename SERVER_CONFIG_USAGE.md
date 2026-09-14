# Guía de Uso - Configuración Dinámica de Servidor

## 🎯 Objetivo
Cambiar la dirección base del servidor en tiempo de ejecución sin necesidad de recompilar la aplicación.

---

## 📖 Cómo Usar

### 1. **Acceder a la Configuración**
1. Busca el icono 🌐 (globo terráqueo) en la barra superior de la aplicación (AppBar)
2. Haz click en él

### 2. **Cambiar la URL del Servidor**
1. Se abrirá un diálogo titulado "Configurar dirección del servidor"
2. En el campo de entrada, ingresa la nueva dirección:
   - Formato válido: `http://localhost:5179`
   - Formato válido: `https://servidor.ejemplo.com:8080`
   - Formato válido: `http://192.168.1.100:5179`
3. Haz click en **"Guardar Configuración"**

### 3. **Validación**
- ✅ La URL debe comenzar con `http://` o `https://`
- ✅ La URL debe tener un formato válido
- ✅ No puede estar vacía

Si la URL no es válida, el diálogo mostrará un mensaje de error en rojo.

### 4. **Guardar Cambios**
- El diálogo mostrará un mensaje de confirmación: "Dirección del servidor actualizada"
- La nueva configuración se guarda automáticamente en los datos locales de la app
- La siguiente vez que abras la app, cargará con esta configuración

### 5. **Resetear a Valor Por Defecto**
1. Si deseas volver a `http://localhost:5179`, haz click en **"Resetear a Valor Por Defecto"**
2. Se abrirá un diálogo de confirmación
3. Confirma para volver al valor por defecto

---

## 🐳 Para Despliegues en Docker

### Escenario Típico
```bash
# Desarrollo local
docker run -e SERVER_URL=http://localhost:5179 mi-app

# QA
docker run -e SERVER_URL=http://qa-server:5179 mi-app

# Producción
docker run -e SERVER_URL=https://api.produccion.com:5179 mi-app
```

**Después del despliegue:**
1. Abre la app
2. Haz click en el globo 🌐
3. Ingresa la URL del servidor correspondiente al ambiente
4. Guarda

---

## 🔧 Comportamiento Técnico

### Donde se Guarda
- Los datos locales (SharedPreferences) en Android
- El UserDefaults en iOS
- Los datos locales en desktop

### Cuando se Aplica
- **Inmediatamente:** Cuando haces click en "Guardar"
- **Próximas llamadas:** Todas las operaciones que requieran conectarse al servidor usarán la nueva URL

### Qué Cambios
✅ Llamadas MCP (procedures, autorizaciones, variables dinámicas)  
✅ Ejecución de procedimientos dinámicos  
✅ Monitoreo de conexión (indicador de estado)  
✅ Carga del schema de base de datos  

### Qué No Cambia
- Los cambios no requieren reiniciar la app
- Los cambios no afectan datos ya cargados en memoria
- El editor sigue funcionando con los datos actuales

---

## 🐛 Solución de Problemas

### "La conexión sigue siendo a la URL anterior"
- **Causa:** Puede haber llamadas en progreso a la URL anterior
- **Solución:** Espera a que terminen o reinicia la app

### "No puedo guardar la configuración"
- **Causa 1:** La URL no es válida
- **Solución:** Verifica que comience con `http://` o `https://`
- **Causa 2:** La URL tiene caracteres especiales no escapados
- **Solución:** Usa URL con formato correcto

### "Cambié el servidor pero no funciona"
- **Causa 1:** El nuevo servidor no está disponible
- **Solución:** Verifica la conectividad y que la URL es correcta
- **Causa 2:** El nuevo servidor no tiene el mismo schema
- **Solución:** Abre el diálogo de configuración > Resetear > Cambiar a servidor correcto

---

## 📱 Interfaz Gráfica

```
┌─────────────────────────────────────────┐
│ ← Atrás  Procedimiento Dinámico  🌐 ⚙️ │
└─────────────────────────────────────────┘
                    ↓
        ┌───────────────────────┐
        │ 🌐 Configurar servidor│
        └───────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Dirección del Servidor                  │
│ ┌─────────────────────────────────────┐ │
│ │ http://localhost:5179               │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ [Guardar Configuración]                 │
│ [Resetear a Valor Por Defecto]          │
│                                         │
│ ✅ Dirección actualizada!               │
└─────────────────────────────────────────┘
```

---

## 💾 Datos Almacenados

**Clave:** `server_base_url`  
**Ubicación:** Datos locales de la aplicación  
**Valor por defecto:** `http://localhost:5179`  
**Formato:** URL completa como string  

---

## ⚡ Performance

- **Primer acceso:** Se consulta SharedPreferences (~1ms)
- **Siguientes accesos:** Se usa caché en memoria (instantáneo)
- **No hay overhead:** Se carga la URL una sola vez por operación

---

## 🔐 Seguridad

- Las URLs se validan antes de usarlas
- No se permiten URLs vacías
- Se verifica formato URI válido
- Las URLs se guardan sin encriptar (considera usar HTTPS en producción)

---

## 📋 Resumen de Atajos

| Acción | Icono | Resultado |
|--------|-------|-----------|
| Abrir configuración | 🌐 | Diálogo de cambio de URL |
| Guardar URL | ✅ | URL se persiste y aplica |
| Resetear | ↶ | Vuelve a `http://localhost:5179` |
| Cancelar | ✕ | Descarta cambios |

---

## 📞 Soporte

Si tienes problemas:
1. Verifica que la URL sea correcta
2. Verifica que el servidor esté disponible
3. Intenta resetear a valor por defecto
4. Reinicia la aplicación
5. Contacta al equipo de soporte con el contenido del log de la app


