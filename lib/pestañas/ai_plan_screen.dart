// lib/pestañas/ai_plan_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../services/training_plan_service.dart';

// ── Paleta ────────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0D0D0E);
const _kSurface = Color(0xFF1C1C1E);
const _kBorder  = Color(0xFF2C2C2E);
const _kDim     = Color(0xFF636366);
const _kSub     = Color(0xFF8E8E93);
const _kWhite   = Color(0xFFEEEEEE);
const _kAccent  = Color(0xFF0A84FF);

TextStyle _t(double size, FontWeight w, Color c, {double spacing = 0}) =>
    GoogleFonts.rajdhani(fontSize: size, fontWeight: w, color: c,
        letterSpacing: spacing);

// ── Modelo de mensaje ─────────────────────────────────────────────────────────
class _AiMsg {
  final bool isUser;
  final String text;
  _AiMsg({required this.isUser, required this.text});
}

// ── Pantalla ──────────────────────────────────────────────────────────────────
class AIPlanScreen extends StatefulWidget {
  final String uid;
  const AIPlanScreen({super.key, required this.uid});
  @override
  State<AIPlanScreen> createState() => _AIPlanScreenState();
}

class _AIPlanScreenState extends State<AIPlanScreen> {
  final _controller     = TextEditingController();
  final _scrollCtrl     = ScrollController();

  late List<_AiMsg> _messages;
  bool _loading = false;
  bool _saving  = false;
  Map<String, dynamic>? _parsedPlan;

  static const _greeting =
      'Hola, soy tu entrenador personal de running. Para crear tu plan '
      'voy a necesitar conocerte un poco.\n\n'
      '¿Cuál es tu objetivo principal? (ej: correr mi primer 5K, bajar '
      'mi marca en 10K, completar una media maratón...)';

  static const _system = '''
Eres un entrenador personal de running experto y motivador. Tu misión es crear un plan de entrenamiento totalmente personalizado para el usuario.

Recopila la siguiente información conversando de forma natural:
1. Objetivo (5K, 10K, media maratón u otro)
2. Nivel de experiencia (principiante, intermedio, avanzado)
3. Días disponibles por semana y cuáles (ej: lunes, miércoles, sábado)
4. Tiempo disponible por sesión
5. Cualquier lesión o limitación física (opcional)

Cuando tengas suficiente información (mínimo: objetivo, nivel y días disponibles), genera el plan en formato JSON dentro de un bloque de código, con EXACTAMENTE esta estructura:

```json
{
  "name": "Mi Plan Personalizado",
  "subtitle": "Generado por IA · 8 semanas",
  "targetLabel": "10 KM",
  "weeks": 8,
  "sessionsPerWeek": 3,
  "sessions": [
    {"week": 1, "slot": 1, "weekday": 1, "type": "easy",      "targetKm": 5.0, "note": "Rodaje suave a ritmo conversacional"},
    {"week": 1, "slot": 2, "weekday": 3, "type": "intervals", "targetKm": 4.0, "note": "6×400 m con 90 s descanso"},
    {"week": 1, "slot": 3, "weekday": 6, "type": "longRun",   "targetKm": 7.0, "note": "Tirada larga tranquila"}
  ]
}
```

Reglas estrictas del JSON:
- "type" solo puede ser: "easy", "intervals", "tempo", "longRun", "race", "rest"
- "weekday": 1=Lunes, 2=Martes, 3=Miércoles, 4=Jueves, 5=Viernes, 6=Sábado, 7=Domingo
- "slot": posición de la sesión en la semana (1, 2, 3…)
- Incluye TODAS las sesiones de TODAS las semanas del plan
- La última sesión del plan debe ser de tipo "race"
- Adapta volumen e intensidad al nivel del usuario
- Responde siempre en español, sé cercano y motivador
''';

  @override
  void initState() {
    super.initState();
    _messages = [_AiMsg(isUser: false, text: _greeting)];
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    final match = RegExp(r'```json\s*(\{[\s\S]*?\})\s*```').firstMatch(text);
    if (match == null) return null;
    try {
      final raw = jsonDecode(match.group(1)!);
      if (raw is Map<String, dynamic> &&
          raw['sessions'] is List &&
          (raw['sessions'] as List).isNotEmpty) {
        return raw;
      }
    } catch (_) {}
    return null;
  }

  // Construye el array de mensajes para la API.
  // El primer mensaje de la lista local es el saludo inicial (assistant), que
  // no puede ir primero en la API de Anthropic. Lo omitimos — el system prompt
  // ya define el rol del asistente.
  List<Map<String, dynamic>> _apiMessages() =>
      _messages.skip(1).map((m) => {
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      }).toList();

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    HapticFeedback.selectionClick();

    setState(() {
      _messages.add(_AiMsg(isUser: true, text: text));
      _loading = true;
    });
    _controller.clear();
    _scrollToBottom();

    if (Env.anthropicApiKey.isEmpty) {
      setState(() => _loading = false);
      _showError('API key de Anthropic no configurada. Rellena Env.anthropicApiKey.');
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': Env.anthropicApiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5-20251001',
          'max_tokens': 4096,
          'system': _system,
          'messages': _apiMessages(),
        }),
      );

      if (res.statusCode == 200) {
        final data  = jsonDecode(utf8.decode(res.bodyBytes));
        final reply = (data['content'] as List).first['text'] as String;
        final plan  = _tryParseJson(reply);
        setState(() {
          _messages.add(_AiMsg(isUser: false, text: reply));
          _loading = false;
          if (plan != null) _parsedPlan = plan;
        });
        _scrollToBottom();
      } else {
        setState(() => _loading = false);
        _showError('Error ${res.statusCode}. Inténtalo de nuevo.');
      }
    } catch (_) {
      setState(() => _loading = false);
      _showError('Sin conexión. Comprueba internet.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _t(13, FontWeight.w500, _kWhite)),
      backgroundColor: _kSurface,
    ));
  }

  Future<void> _guardarPlan() async {
    if (_parsedPlan == null || _saving) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      await TrainingPlanService.startAiPlan(widget.uid, _parsedPlan!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _saving = false);
      _showError('No se pudo guardar el plan. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _kWhite, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: _kAccent, size: 14),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ENTRENADOR IA',
                style: _t(13, FontWeight.w700, _kWhite, spacing: 1.5)),
            Text('Plan personalizado',
                style: _t(10, FontWeight.w400, _kSub)),
          ]),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: _kBorder),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: _messages.length + (_loading ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _messages.length) return const _TypingIndicator();
              return _MessageBubble(msg: _messages[i]);
            },
          ),
        ),
        if (_parsedPlan != null) _buildPlanBanner(),
        _buildInput(),
      ]),
    );
  }

  Widget _buildPlanBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: _kAccent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.check_circle_rounded, color: _kAccent, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Text('Plan generado y listo para guardar',
            style: _t(12, FontWeight.w600, _kAccent)),
      ),
      GestureDetector(
        onTap: _guardarPlan,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _kAccent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _saving
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 1.5))
              : Text('GUARDAR',
                  style: _t(11, FontWeight.w800, Colors.white, spacing: 1)),
        ),
      ),
    ]),
  );

  Widget _buildInput() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottom),
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _kBorder),
            ),
            child: TextField(
              controller: _controller,
              style: _t(14, FontWeight.w400, _kWhite),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Escribe tu mensaje...',
                hintStyle: _t(14, FontWeight.w400, _kDim),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.fromLTRB(16, 10, 16, 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(
                color: _kAccent, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_upward_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}

// ── Burbuja de mensaje ────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final _AiMsg msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;

    // Elimina bloques JSON del texto visible para mantener el chat limpio
    var display = msg.text
        .replaceAll(RegExp(r'```json[\s\S]*?```'), '')
        .trim();
    if (display.isEmpty && !isUser) {
      display = 'He generado tu plan de entrenamiento personalizado.';
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 4, bottom: 4,
        left: isUser ? 52 : 0,
        right: isUser ? 0 : 52,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: isUser ? _kAccent : _kSurface,
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(18),
              topRight:    const Radius.circular(18),
              bottomLeft:  Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            boxShadow: isUser
                ? [BoxShadow(
                    color: _kAccent.withValues(alpha: 0.25),
                    blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Text(display,
              style: _t(14, FontWeight.w400,
                  isUser ? Colors.white : _kWhite)),
        ),
      ),
    );
  }
}

// ── Indicador de escritura animado ────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, right: 52),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.only(
              topLeft:     Radius.circular(18),
              topRight:    Radius.circular(18),
              bottomLeft:  Radius.circular(4),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_anim.value + i * 0.33) % 1.0;
                final opacity = t < 0.5 ? t * 2 : (1 - t) * 2;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: 0.3 + opacity * 0.7,
                    child: Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                          color: _kDim, shape: BoxShape.circle),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
