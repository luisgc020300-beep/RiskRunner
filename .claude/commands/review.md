# /review — Revisión de código antes de commitear

Revisa los cambios staged (y unstaged si no hay staged) como un senior engineer. Responde en español.

## Proceso

1. Ejecutar `git diff --staged` para ver cambios staged. Si está vacío, usar `git diff` (unstaged).
2. Ejecutar `git status` para ver qué archivos están involucrados.
3. Revisar cada archivo modificado con criterio estricto.

## Criterios de revisión

### Seguridad (bloqueante)
- ¿Algún cambio expone secrets, API keys o datos de usuario?
- ¿Hay SQL/NoSQL injection o XSS posible?
- ¿Se modifican reglas de Firestore o Cloud Functions? ¿Son seguras?
- ¿`lib/config/env.dart` aparece en los cambios? → PARAR inmediatamente

### Corrección (bloqueante)
- ¿Hay `setState` sin `if (mounted)` después de un `await`?
- ¿Hay `.withOpacity()` (usar `.withValues(alpha:)` en su lugar)?
- ¿Hay catches vacíos `catch (_) {}` sin log?
- ¿Hay lógica de negocio crítica (monedas, territorios) sin transacción atómica?
- ¿Los tipos son correctos? ¿Hay null safety correcta?

### Estándares RiskRunner (alerta)
- ¿Hay emojis en la UI en vez de `Icon(Icons.xxx)`?
- ¿Hay `FontWeight.w900` o `letterSpacing > 2`?
- ¿Se usa `.withOpacity()` en vez de `.withValues(alpha:)`?
- ¿Los colores hardcoded en vez de usar `AppColors`?
- ¿Los archivos nuevos siguen el naming `snake_case`?

### Calidad (info)
- ¿El código hace lo que parece que hace?
- ¿Hay duplicación evitable?
- ¿Los métodos son razonablemente cortos y con nombres claros?
- ¿Se necesitan tests para los cambios? ¿Los hay?

## Formato de respuesta

Lista de hallazgos por archivo, clasificados como BLOQUEANTE / ALERTA / INFO.
Si no hay bloqueantes: "✅ Listo para commit" con resumen de 1 línea.
Si hay bloqueantes: "🚫 No commitear hasta resolver:" con lista exacta de qué corregir.
