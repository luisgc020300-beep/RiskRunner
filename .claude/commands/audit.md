# /audit — Auditoría completa de RiskRunner

Ejecuta una auditoría completa del proyecto en tres dimensiones. Responde en español.

## 1. Seguridad
- Verificar que `lib/config/env.dart` no está en git staging: `git status`
- Buscar hardcoded API keys, tokens o secrets en `lib/`: `grep -r "sk-" lib/ --include="*.dart"`
- Buscar `withOpacity` (deprecated): contar ocurrencias en `lib/`
- Verificar que no hay catches vacíos `catch (_) {}` sin log

## 2. Calidad de código
- Ejecutar `dart analyze lib/` y reportar errores y warnings (ignorar infos de file_names)
- Contar líneas de los ficheros grandes: `wc -l lib/pestañas/LiveActivity_screen.dart lib/pestañas/fullscreen_map_screen.dart`
- Verificar que los guards `if (mounted)` están presentes en los métodos async con setState

## 3. Tests
- Ejecutar `flutter test` y reportar resultado: cuántos pasan, cuántos fallan
- Identificar servicios sin test en `lib/services/`

## Formato de respuesta
Responde con tres secciones: SEGURIDAD / CÓDIGO / TESTS. Cada sección con estado (OK / ALERTA / CRÍTICO) y lista de hallazgos concretos. Termina con una lista priorizada de acciones.
