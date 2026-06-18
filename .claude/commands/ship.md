# /ship — Checklist pre-release

Verifica que la app está lista para subir a stores. Responde en español.

## Checklist obligatorio

### Seguridad (bloqueante)
- [ ] `git status` — confirmar que `lib/config/env.dart` NO aparece en staged/modified
- [ ] `git log --oneline -5` — revisar que los últimos commits no incluyen env.dart
- [ ] Buscar secrets hardcoded: `grep -rn "sk-ant\|AIza\|mapbox_secret" lib/`
- [ ] RevenueCat keys vacías si no hay cuentas de stores confirmadas

### Calidad (bloqueante)
- [ ] `dart analyze lib/` — cero errores, cero warnings
- [ ] `flutter test` — 0 tests fallando
- [ ] LiveActivity_screen.dart < 5000 líneas
- [ ] fullscreen_map_screen.dart < 4500 líneas

### Build (bloqueante)
- [ ] `flutter build apk --release` o `flutter build ios --release` sin errores
- [ ] Version en `pubspec.yaml` incrementada respecto al último release

### Producto (recomendado)
- [ ] Screenshots actualizadas para stores
- [ ] Changelog redactado para esta versión
- [ ] Crashlytics activo y con DSym/mapping file subido

## Formato de respuesta
Estado final: LISTO / BLOQUEADO con lista de items que fallan. Si hay bloqueantes, indicar exactamente cómo resolverlos.
