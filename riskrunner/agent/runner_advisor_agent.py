"""
RiskRunner — Runner Advisor Agent
==================================
Agente autónomo que analiza la app, hace investigación de mercado,
identifica oportunidades y genera informes de producto.

Uso:
    python runner_advisor_agent.py [comando]

Comandos:
    audit           Análisis completo del estado actual de la app
    market          Investigación de mercado y competidores
    features        Priorización de features pendientes
    ux              Revisión de UX desde perspectiva de runner
    report          Genera informe ejecutivo combinado

Requisitos:
    pip install anthropic

Variables de entorno:
    ANTHROPIC_API_KEY  — tu clave de API de Anthropic
"""

import anthropic
import os
import sys
import json
import subprocess
from pathlib import Path
from datetime import datetime

# ── Config ────────────────────────────────────────────────────────────────────
MODEL         = "claude-opus-4-8"
PROJECT_ROOT  = Path(__file__).parent.parent.parent  # c:/dev/mi_app
REPORTS_DIR   = Path(__file__).parent / "reports"
REPORTS_DIR.mkdir(exist_ok=True)

# ── Cargar .env si existe ─────────────────────────────────────────────────────
_env_file = Path(__file__).parent / ".env"
if _env_file.exists():
    for line in _env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

# ── System prompt ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """
Eres el asesor de producto de RiskRunner, una app de running con mecánica de
conquista territorial. Tu rol combina tres perfiles:

1. RUNNER EXPERTO: Conoces la psicología del corredor urbano casual (25-40 años,
   3-5 sesiones/semana, motivación social y de logro). Sabes qué le frustra de
   Strava, qué le gusta de Nike Run Club, y por qué la territorialidad es
   emocionalmente poderosa.

2. ANALISTA DE MERCADO: Conoces el landscape competitivo (Strava, Nike Run Club,
   Garmin Connect, Komoot, AllTrails, Runtastic) con sus fortalezas y debilidades.
   Puedes identificar gaps de mercado y oportunidades de diferenciación.

3. PRODUCT MANAGER TÉCNICO: Entiendes Flutter/Firebase, puedes leer código y
   evaluar complejidad de implementación. Priorizas con criterios de retención,
   diferenciación, velocidad de desarrollo y monetización.

PRINCIPIO CORE DE RISKRUNNER:
"Cada carrera cambia el mapa. El runner conquista su barrio, reta a rivales
reales, y sus piernas deciden quién manda en el territorio."

Al analizar o sugerir features, siempre pregúntate:
- ¿Hace al runner volver mañana?
- ¿Refuerza la mecánica de conquista territorial?
- ¿Ningún competidor lo hace igual?
- ¿Lo entendería un runner casual en < 10 segundos?

Sé directo, específico y práctico. Nada de recomendaciones genéricas.
Cada sugerencia debe incluir: QUÉ, POR QUÉ importa al runner, y estimación
de esfuerzo (horas/días de desarrollo Flutter).
"""

# ── Herramientas disponibles ───────────────────────────────────────────────────
def read_codebase_structure() -> dict:
    """Mapea la estructura de lib/ para contexto del agente."""
    structure = {}
    lib_path = PROJECT_ROOT / "lib"
    if not lib_path.exists():
        return {"error": "lib/ not found"}

    for path in sorted(lib_path.rglob("*.dart")):
        rel = str(path.relative_to(lib_path))
        size = path.stat().st_size
        structure[rel] = {"size_bytes": size}

    return structure

def read_dart_file(relative_path: str) -> str:
    """Lee un archivo Dart del proyecto."""
    full_path = PROJECT_ROOT / "lib" / relative_path
    if not full_path.exists():
        return f"ERROR: {relative_path} no encontrado"
    return full_path.read_text(encoding="utf-8")

def run_flutter_analyze() -> str:
    """Ejecuta flutter analyze y devuelve el resultado."""
    try:
        result = subprocess.run(
            ["flutter", "analyze", "--no-pub"],
            capture_output=True, text=True, cwd=str(PROJECT_ROOT), timeout=120
        )
        return result.stdout + result.stderr
    except Exception as e:
        return f"Error ejecutando flutter analyze: {e}"

def get_git_log(n: int = 20) -> str:
    """Últimos N commits del repo."""
    try:
        result = subprocess.run(
            ["git", "log", f"-{n}", "--oneline"],
            capture_output=True, text=True, cwd=str(PROJECT_ROOT)
        )
        return result.stdout
    except Exception as e:
        return f"Error: {e}"

def save_report(content: str, report_type: str) -> str:
    """Guarda un informe en reports/."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    filename = REPORTS_DIR / f"{report_type}_{timestamp}.md"
    filename.write_text(content, encoding="utf-8")
    return str(filename)

# ── Definición de tools para Claude ───────────────────────────────────────────
TOOLS = [
    {
        "name": "read_codebase_structure",
        "description": "Obtiene la lista completa de archivos Dart en lib/ con sus tamaños. Útil para entender la arquitectura del proyecto antes de leer archivos específicos.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "read_dart_file",
        "description": "Lee el contenido de un archivo Dart del proyecto. Usar para analizar screens, widgets, servicios o modelos específicos.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Ruta relativa desde lib/, ej: 'pestañas/Home_screen.dart'"
                }
            },
            "required": ["path"]
        }
    },
    {
        "name": "run_flutter_analyze",
        "description": "Ejecuta flutter analyze para detectar warnings y errores en el código.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_git_log",
        "description": "Obtiene el historial reciente de commits para entender qué se ha implementado recientemente.",
        "input_schema": {
            "type": "object",
            "properties": {
                "n": {
                    "type": "integer",
                    "description": "Número de commits a mostrar (default 20)",
                    "default": 20
                }
            },
            "required": []
        }
    },
    {
        "name": "save_report",
        "description": "Guarda el análisis final como archivo Markdown en reports/.",
        "input_schema": {
            "type": "object",
            "properties": {
                "content": {
                    "type": "string",
                    "description": "Contenido del informe en Markdown"
                },
                "report_type": {
                    "type": "string",
                    "description": "Tipo de informe: audit, market, features, ux, report"
                }
            },
            "required": ["content", "report_type"]
        }
    }
]

# ── Motor del agente ───────────────────────────────────────────────────────────
def process_tool_call(tool_name: str, tool_input: dict) -> str:
    if tool_name == "read_codebase_structure":
        result = read_codebase_structure()
        return json.dumps(result, indent=2)
    elif tool_name == "read_dart_file":
        return read_dart_file(tool_input["path"])
    elif tool_name == "run_flutter_analyze":
        return run_flutter_analyze()
    elif tool_name == "get_git_log":
        return get_git_log(tool_input.get("n", 20))
    elif tool_name == "save_report":
        path = save_report(tool_input["content"], tool_input["report_type"])
        return f"Informe guardado en: {path}"
    else:
        return f"Tool desconocida: {tool_name}"

def run_agent(user_prompt: str, verbose: bool = True) -> str:
    """Ejecuta el agente con agentic loop hasta que termine."""
    client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))

    messages = [{"role": "user", "content": user_prompt}]
    final_text = ""

    while True:
        response = client.messages.create(
            model=MODEL,
            max_tokens=8192,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )

        # Recoger texto del modelo
        for block in response.content:
            if hasattr(block, "text"):
                final_text += block.text
                if verbose:
                    print(block.text, end="", flush=True)

        # Si terminó, salir
        if response.stop_reason == "end_turn":
            break

        # Si hay tool use, procesarlo
        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    if verbose:
                        print(f"\n[TOOL] {block.name}({json.dumps(block.input)[:100]}...)")
                    result = process_tool_call(block.name, block.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result
                    })

            # Añadir respuesta del modelo y resultados al historial
            messages.append({"role": "assistant", "content": response.content})
            messages.append({"role": "user", "content": tool_results})
        else:
            break

    return final_text

# ── Comandos ───────────────────────────────────────────────────────────────────
PROMPTS = {
    "audit": """
Analiza el estado actual de RiskRunner como si fueras un senior PM llegando al proyecto.
1. Lee la estructura del codebase y los últimos 30 commits
2. Identifica las pantallas/features principales implementadas
3. Detecta inconsistencias UX, deuda técnica visible, o features a medias
4. Da una nota de completitud al producto (0-10) y justifícala
5. Lista los 5 problemas más críticos a resolver para llegar a v1.0 lista para lanzar
Guarda el informe como 'audit'.
""",

    "market": """
Haz un análisis de mercado de RiskRunner vs competidores.
1. Lee el historial de commits para entender qué features tiene actualmente
2. Lee Home_screen.dart, perfil_screen.dart y fullscreen_map_screen.dart para entender el producto real
3. Compara feature por feature con: Strava, Nike Run Club, Garmin Connect
4. Identifica los 3 gaps más grandes que impiden que un runner deje Strava por RiskRunner
5. Identifica las 3 ventajas únicas que RiskRunner tiene y que debe potenciar
6. Propón 5 features concretas para cerrar gaps críticos, ordenadas por ROI
Guarda el informe como 'market'.
""",

    "features": """
Genera un backlog priorizado de features para RiskRunner.
1. Lee la estructura del proyecto y commits recientes
2. Lee los archivos principales de la app (Home, Perfil, Mapa, Social)
3. Para cada área, identifica qué falta vs lo que haría un runner volver cada día
4. Crea un backlog en formato tabla: Feature | Área | Impacto retención (1-5) | Esfuerzo días (1-5) | Diferenciación (1-5) | Prioridad
5. Explica el top 10 con detalle: qué es, por qué importa al runner, cómo implementarlo en Flutter
Guarda el informe como 'features'.
""",

    "ux": """
Haz una auditoría UX de RiskRunner desde la perspectiva de un runner casual de 30 años.
1. Lee las pantallas principales: Home, Correr (si existe), Mapa, Social, Perfil, Notificaciones
2. Para cada pantalla evalúa: claridad de propósito, fricción en tareas clave, feedback visual, coherencia dark/light mode
3. Identifica los 3 flujos más importantes del usuario y mapea dónde hay fricción
4. Lista quick wins de UX (cambios < 2h de desarrollo que mejoran significativamente la experiencia)
5. Lista mejoras estructurales de UX que requieren más tiempo pero son críticas
Guarda el informe como 'ux'.
""",

    "report": """
Genera el informe ejecutivo completo de RiskRunner.
1. Lee el codebase completo (estructura + archivos clave)
2. Analiza el historial git para entender la evolución
3. Crea un informe ejecutivo con: estado del producto, posicionamiento de mercado, fortalezas, debilidades, oportunidades, amenazas (SWOT), y roadmap recomendado para los próximos 3 meses
4. Incluye métricas objetivo para saber si el lanzamiento es exitoso
5. Da una recomendación de go-to-market: ¿cómo lanzar, en qué plataforma primero, cómo conseguir los primeros 1000 usuarios?
Guarda el informe como 'report'.
"""
}

# ── Main ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in PROMPTS:
        print(__doc__)
        print(f"\nComandos disponibles: {', '.join(PROMPTS.keys())}")
        sys.exit(1)

    command = sys.argv[1]
    print(f"\n{'='*60}")
    print(f"RiskRunner Runner Advisor Agent — {command.upper()}")
    print(f"Modelo: {MODEL}")
    print(f"{'='*60}\n")

    result = run_agent(PROMPTS[command])
    print(f"\n\n{'='*60}")
    print(f"Análisis completado. Informe guardado en riskrunner/agent/reports/")
