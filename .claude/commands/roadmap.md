# /roadmap — Estado actual y próximos pasos

Genera un snapshot del estado real de RiskRunner y decide qué hacer esta semana. Responde en español.

## Proceso

1. Leer `CLAUDE.md` para contexto del proyecto.
2. Ejecutar `git log --oneline -10` para ver qué se ha hecho recientemente.
3. Ejecutar `git status` para ver trabajo sin commitear.
4. Revisar estado de archivos clave: líneas de LiveActivity y fullscreen_map.
5. Leer `.claude/commands/` para recordar qué comandos existen.

## Secciones del informe

### Estado técnico (semáforo)
- Tests: N/N pasando
- dart analyze: errores / warnings
- LiveActivity_screen.dart: N líneas (objetivo <4,500)
- fullscreen_map_screen.dart: N líneas (objetivo <4,000)
- Trabajo sin commitear: sí/no, qué archivos

### Deuda técnica pendiente
Lista corta (máx 5 items) de los problemas técnicos reales que quedan, con impacto estimado.

### Plan visual — estado
- Fase 1 (tokens/tipografía): completada / en progreso / pendiente
- Fase 2 (identidad/botones): completada / en progreso / pendiente  
- Fase 3 (HUD táctico/iconos): completada / en progreso / pendiente

### Producto — próximas features
Top 3 features pendientes puntuadas con el framework (Retención / Diferenciación / Coste / Efecto red / Monetizable).

### Contexto de negocio
- Estado de lanzamiento: bloqueado por / previsto para
- Presupuesto disponible / necesario
- Acciones de comunidad/marketing activas

## Recomendación de la semana
Una sola cosa: qué atacar esta semana y por qué. Justificado por impacto real, no por lo que es más fácil.

## Formato de respuesta
Informe ejecutivo conciso. Máximo 40 líneas. Lo que el CEO necesita saber para tomar decisiones, no un volcado de datos.
