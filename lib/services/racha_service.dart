// lib/services/racha_service.dart
//
// La racha diaria se calcula enteramente en el servidor (Cloud Function
// 'actualizarRachaDiaria') usando la hora del propio proceso — antes se
// leía/escribía directamente desde el cliente sin transacción, con riesgo
// de condición de carrera. El cliente solo manda su offset de zona horaria,
// para que el corte de "día" coincida con lo que el usuario percibe.
//
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class RachaResultado {
  final int racha;
  final bool yaContadaHoy;
  const RachaResultado({required this.racha, required this.yaContadaHoy});
}

class RachaService {
  static final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<RachaResultado?> actualizarRachaDiaria() async {
    try {
      final result = await _functions.httpsCallable('actualizarRachaDiaria').call({
        'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      });
      return RachaResultado(
        racha: (result.data['racha'] as num).toInt(),
        yaContadaHoy: result.data['yaContadaHoy'] as bool,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error actualizarRachaDiaria (${e.code}): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error actualizarRachaDiaria: $e');
      return null;
    }
  }
}
