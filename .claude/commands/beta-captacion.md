# /beta-captacion — Sistema de captación de beta testers

Modo Jarvis de captación de 100 beta testers en Granada antes del 5 de julio 2026.
Canal principal: Instagram manual (10-15 DMs/día). Canal secundario: formulario en /beta.html.

Responde siempre en español.

---

## Uso

```
/beta-captacion                     → resumen del pipeline
/beta-captacion targets             → genera lista de 15 cuentas a contactar hoy
/beta-captacion dm @handle [bio]    → genera DM personalizado para ese perfil
/beta-captacion report              → estado completo del pipeline
/beta-captacion followup            → quién necesita seguimiento hoy
```

---

## 1. Pipeline — cómo leer el estado actual

Lee el archivo de tracking local: `beta_outreach.csv`
Si no existe, créalo con estas columnas:

```
instagram_handle,nombre,fecha_contacto,dispositivo,status,notas
```

Estados válidos: `contactado` | `interesado` | `confirmado` | `no_interesado` | `sin_respuesta`

Para añadir un contacto:
```bash
echo "@handle,,$(date +%Y-%m-%d),ios,contactado," >> beta_outreach.csv
```

---

## 2. Resumen del pipeline (modo sin argumento)

Cuando se invoca sin argumentos:

1. Lee `beta_outreach.csv` si existe
2. Cuenta por estado
3. Consulta cuántos hay en Firestore `beta_candidates` (formulario web)
4. Muestra:

```
PIPELINE BETA — [fecha]
─────────────────────────────────
Outreach manual (Instagram DMs)
  Contactados totales:   XX
  Interesados:           XX
  Confirmados:           XX
  Sin respuesta:         XX
  No interesados:        XX

Formulario web (/beta.html)
  Registros totales:     XX

TOTAL testers confirmados: XX / 100
Ritmo necesario: XX/día para llegar a 100 el 5 jul
─────────────────────────────────
```

Para consultar Firestore, usa:
```bash
firebase firestore:query beta_candidates --project runnerriskapp 2>/dev/null | grep -c "instagram_handle" || echo "0"
```
Si el CLI no está disponible, indica "datos web no disponibles — despliega functions primero".

---

## 3. Generar lista de targets (`targets`)

Genera 15 cuentas/perfiles a buscar hoy en Instagram. NO son usernames reales — son criterios de búsqueda.

### Hashtags donde buscar runners en Granada:
```
#corredoresgranada    #runninggranada      #trailgranada
#granadatrail         #corredoresdeespana  #runnersgranada
#athletesgranada      #corredoresurbanos   #maratongranada
#10kgranada           #circuitogranada     #parkrungranada
```

### Búsqueda por ubicación:
- Parque García Lorca (mención frecuente en runners del Sur)
- Paseo del Salón
- Carretera de La Sierra / Cenes
- Alhambra running routes

### Criterios de un buen target:
- Bio menciona "correr", "running", "trail", "km" o similar
- Publica contenido de running en los últimos 30 días
- Tiene entre 100 y 10.000 seguidores (micro-influencer o usuario activo)
- Ubicación: Granada o mencionan Granada en posts

### Output esperado:
Lista de hashtags a buscar + perfil de candidato ideal. El CEO buscará manualmente y te dará handles para generar DMs.

---

## 4. Generar DM personalizado (`dm @handle [bio]`)

Cuando se llama con un handle (y opcionalmente la bio del perfil):

Genera un DM corto, natural y personalizado. Reglas:
- Máximo 3 frases. No más.
- Tono: directo, de runner a runner. No marketing.
- Mencionar Granada explícitamente.
- No mencionar "beta" en el asunto inicial — primero enganchar.
- Si tienes la bio, personaliza con algo específico (distancia, zona, evento mencionado).

### Plantilla base:
```
Hola [NOMBRE/handle]! Vi que corres por Granada 👟 Estoy desarrollando una app donde cada carrera que haces conquista territorios reales en el mapa — tipo guerra de calles entre runners. Estamos buscando los primeros testers en Granada antes del lanzamiento. ¿Te interesa probarlo gratis?
```

### Variante con bio (si menciona trail):
```
Hola! Vi que haces trail por Granada 🏔 Estoy desarrollando RiskRunner — una app donde cada ruta que corres conquista zonas reales del mapa y puedes atacar los territorios de otros runners. Buscamos testers en Granada antes del lanzamiento. ¿Te apuntas?
```

### Variante si no hay bio:
```
Hola! Eres runner en Granada? Estoy desarrollando una app donde cada carrera conquista territorios del mapa real de la ciudad — hay PvP entre runners. Buscamos 100 testers para la beta. Totalmente gratis. ¿Te interesa?
```

### Si responden con interés, segunda respuesta:
```
Perfecto! Te mando el link para reservar tu plaza: runnerriskapp.web.app/beta
Dísponible para iOS y Android. El acceso se abre el 5 de julio.
```

---

## 5. Seguimiento (`followup`)

Lee `beta_outreach.csv` y muestra:
- Cuentas con status `contactado` o `sin_respuesta` cuya `fecha_contacto` fue hace más de 48h
- Ordenadas por fecha (más antiguas primero)

Para cada una, genera el mensaje de seguimiento:
```
Hola de nuevo! Solo quería saber si pudiste ver mi mensaje sobre RiskRunner. 
El acceso beta se abre el 5 de julio en Granada. ¿Te apuntamos?
```

Límite: mostrar máximo 10. Si hay más, indicar cuántos quedan.

---

## 6. Registrar contacto en el CSV

Cuando el CEO confirma que ha enviado un DM a un perfil, añade al CSV:

```bash
# Añadir contacto nuevo
$handle = "@ejemplo"
$fecha = Get-Date -Format "yyyy-MM-dd"  # PowerShell
echo "$handle,,$(date +%Y-%m-%d),desconocido,contactado," >> beta_outreach.csv
```

Cuando el CEO reporta una respuesta, actualiza el status:
```bash
# Esto requiere editar el CSV manualmente — indica al CEO qué línea cambiar
```

---

## 7. Métricas clave a monitorizar

| Métrica | Objetivo | Cómo medir |
|---------|----------|------------|
| DMs enviados/día | 10-15 | `beta_outreach.csv` |
| Tasa respuesta | >30% | interesados / contactados |
| Tasa conversión | >60% de interesados | confirmados / interesados |
| Testers totales | 100 antes del 5 jul | CSV + Firestore |

Con 15 DMs/día y 30% respuesta + 60% conversión = ~3 testers/día → 45 en 15 días.
Para llegar a 100: necesitas también el formulario web y referidos.

---

## 8. Canales complementarios (sin DMs fríos)

Cuando los DMs se agoten o la cuenta tenga bajo engagement, usar:

- **Grupos de Facebook:** "Runners Granada", "Corredores Sierra Nevada" — post en grupo preguntando por testers
- **Strava clubs locales:** buscar clubs de Granada y comentar en actividades recientes
- **Foros:** corredores.es subforums locales
- **WhatsApp:** grupos de running de Granada (pedir al CEO si tiene acceso)

Para cada canal, generar copy específico cuando se solicite.
