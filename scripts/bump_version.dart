// scripts/bump_version.dart
//
// Uso:  dart run scripts/bump_version.dart [patch|minor|major]
//
// Ejemplos:
//   dart run scripts/bump_version.dart patch   →  1.0.0+1 → 1.0.1+2
//   dart run scripts/bump_version.dart minor   →  1.0.1+2 → 1.1.0+3
//   dart run scripts/bump_version.dart major   →  1.1.0+3 → 2.0.0+4

import 'dart:io';

void main(List<String> args) {
  final bump = args.isEmpty ? 'patch' : args.first;
  if (!{'patch', 'minor', 'major'}.contains(bump)) {
    stderr.writeln('Uso: dart run scripts/bump_version.dart [patch|minor|major]');
    exit(1);
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('Error: pubspec.yaml no encontrado. Ejecuta desde la raíz del proyecto.');
    exit(1);
  }

  final content = pubspec.readAsStringSync();
  final versionRegex = RegExp(r'^version:\s+(\d+)\.(\d+)\.(\d+)\+(\d+)', multiLine: true);
  final match = versionRegex.firstMatch(content);

  if (match == null) {
    stderr.writeln('Error: no se encontró línea "version: x.y.z+b" en pubspec.yaml');
    exit(1);
  }

  var major = int.parse(match.group(1)!);
  var minor = int.parse(match.group(2)!);
  var patch = int.parse(match.group(3)!);
  final build = int.parse(match.group(4)!);

  switch (bump) {
    case 'major': major++; minor = 0; patch = 0;
    case 'minor': minor++; patch = 0;
    case 'patch': patch++;
  }

  final newVersion = '$major.$minor.$patch+${build + 1}';
  final updated = content.replaceFirst(versionRegex, 'version: $newVersion');
  pubspec.writeAsStringSync(updated);

  final old = '${match.group(1)}.${match.group(2)}.${match.group(3)}+${match.group(4)}';
  stdout.writeln('Version: $old → $newVersion');
}
