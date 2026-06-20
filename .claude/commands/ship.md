# /ship — Checklist pre-release

Verifica que la app está lista para subir a stores. Responde en español.
Ejecuta cada comprobación activamente — no la marques como ok sin verificarla.

## 1. Seguridad (BLOQUEANTE)

- [ ] `git status` — confirmar que `lib/config/env.dart` NO aparece en staged/modified
- [ ] `git log --oneline -5` — revisar que los últimos commits no incluyen env.dart
- [ ] `grep -rn "sk-ant\|AIza\|pk.eyJ\|mapbox_secret" lib/` — cero resultados
- [ ] RevenueCat keys vacías mientras no haya cuentas de stores confirmadas
- [ ] Firestore rules (`firestore.rules`) — confirmar que no hay reglas `allow: true` sin condición

## 2. Calidad (BLOQUEANTE)

- [ ] `flutter analyze` — cero errores, cero warnings (infos de naming: permitidos)
- [ ] `flutter test` — 0 tests fallando
- [ ] `git diff --stat HEAD~1` — revisar que no hay archivos no intencionados en el commit

## 3. Versión y branch (BLOQUEANTE)

- [ ] Branch actual es `main` o `release/x.x.x` (no `develop` ni `feature/xxx`)
- [ ] `grep '^version:' pubspec.yaml` — versión incrementada respecto al release anterior
- [ ] Build number único: mayor que el último subido a App Store Connect / Play Console
- [ ] `git tag` — existe el tag `vX.Y.Z` correspondiente a esta versión

## 4. Build (BLOQUEANTE)

- [ ] `make build-prod-ios` o `make build-prod-android` — sin errores de compilación
- [ ] El `.ipa` o `.aab` generado pesa razonablemente (<100 MB sin assets grandes)

## 5. Crashlytics (RECOMENDADO)

- [ ] `build/symbols/ios/` existe y tiene archivos `.symbols` (para obfuscated build)
- [ ] Subir DSym a Firebase: `firebase crashlytics:symbols:upload --app=APP_ID build/symbols/ios/`
- [ ] En Crashlytics dashboard: confirmar que llegan eventos de la build de staging antes de subir prod

## 6. TestFlight — iOS (cuando exista Apple Developer)

> Prerrequisito: Apple Developer Program €99/año + cuenta App Store Connect

- [ ] Bundle ID `com.riskrunner.app` registrado en App Store Connect
- [ ] Certificado de distribución válido en Xcode
- [ ] Provisioning profile actualizado con todos los devices de testing
- [ ] Subir `.ipa` con Xcode Organizer o `xcrun altool --upload-app`
- [ ] En App Store Connect → TestFlight: añadir testers internos (hasta 100 sin revisión)
- [ ] Notas de versión redactadas en español para los testers
- [ ] Esperar procesamiento (~15 min) antes de notificar a testers

## 7. Google Play — Android (cuando exista cuenta Play)

> Prerrequisito: Google Play Developer €25 pago único

- [ ] `.aab` firmado con keystore de producción (NO el debug keystore)
- [ ] Keystore guardada en lugar seguro fuera del repo
- [ ] Subir a Play Console → Pruebas internas (hasta 100 sin revisión)
- [ ] Rellenar ficha de la app: descripción, capturas, clasificación de edad

## 8. Post-release

- [ ] `git push origin main && git push origin vX.Y.Z` — tag y main en remoto
- [ ] Merge `main` → `develop` para sincronizar el build number bumpeado
- [ ] Anotar en el historial qué features incluye esta versión

## Formato de respuesta

Estado: **LISTO** / **BLOQUEADO**

Si BLOQUEADO: listar exactamente qué falla y cómo resolverlo (archivo, línea, comando).
Si LISTO: confirmar versión, build number y próximo paso (subir a TestFlight/Play o esperar accounts).
