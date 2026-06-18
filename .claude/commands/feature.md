# /feature — Plan de implementación de feature

Dado el nombre o descripción de una feature, genera un plan completo antes de tocar código.
Argumento: $ARGUMENTS (nombre/descripción de la feature)

## Análisis previo

### 1. Encaje con el producto
- ¿Refuerza la UVP de RiskRunner (conquista territorial + rivalidad local)?
- ¿Impacto en retención D1/D7/D30?
- ¿Lo hace algún competidor (Strava, Nike RC)? ¿Cómo?
- Puntuación según framework: Retención / Diferenciación / Coste / Efecto red / Monetizable (1-5 cada uno)

### 2. Análisis técnico
- ¿Qué archivos se modifican? Listar con ruta completa
- ¿Nuevos servicios o modelos de datos necesarios?
- ¿Cambios en Firestore (índices, reglas de seguridad)?
- ¿Cloud Functions necesarias?
- ¿Riesgos de regresión en features existentes?

### 3. Plan de implementación
Pasos ordenados y concretos. Cada paso debe ser atómico y verificable.

### 4. Criterio de éxito
- ¿Qué debe funcionar exactamente para considerar la feature completa?
- ¿Qué tests hay que añadir?

## Formato de respuesta
Responde con las 4 secciones. Al final, una recomendación clara: IMPLEMENTAR / POSPONER / DESCARTAR con razón.
No implementes nada hasta que el CEO apruebe el plan.
