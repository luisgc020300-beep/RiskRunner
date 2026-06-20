# Makefile — RiskRunner build & release commands
# Uso: make <target>
#
# Prerrequisitos: flutter, firebase CLI, git

VERSION := $(shell grep '^version:' pubspec.yaml | awk '{print $$2}')

# ── Dev ───────────────────────────────────────────────────────────────────────
run-dev:
	flutter run --dart-define=FLAVOR=dev

run-dev-android:
	flutter run -d android --dart-define=FLAVOR=dev

# ── Staging (para QA interno / TestFlight staging track) ─────────────────────
build-staging-ios:
	flutter build ipa \
	  --dart-define=FLAVOR=staging \
	  --build-name=$(shell echo $(VERSION) | cut -d+ -f1) \
	  --build-number=$(shell date +%Y%m%d%H) \
	  --release

build-staging-android:
	flutter build appbundle \
	  --dart-define=FLAVOR=staging \
	  --release

# ── Prod (para App Store / Google Play) ──────────────────────────────────────
# Antes de ejecutar: git tag v$(VERSION) && git push origin v$(VERSION)
build-prod-ios:
	@echo "🔒  Verificando que env.dart no está staged..."
	@git diff --cached --name-only | grep -q "env.dart" && echo "❌  env.dart está staged. Abortar." && exit 1 || true
	flutter build ipa \
	  --dart-define=FLAVOR=prod \
	  --build-name=$(shell echo $(VERSION) | cut -d+ -f1) \
	  --build-number=$(shell date +%Y%m%d%H%M) \
	  --obfuscate \
	  --split-debug-info=build/symbols/ios \
	  --release

build-prod-android:
	@git diff --cached --name-only | grep -q "env.dart" && echo "❌  env.dart está staged. Abortar." && exit 1 || true
	flutter build appbundle \
	  --dart-define=FLAVOR=prod \
	  --build-name=$(shell echo $(VERSION) | cut -d+ -f1) \
	  --build-number=$(shell date +%Y%m%d%H%M) \
	  --obfuscate \
	  --split-debug-info=build/symbols/android \
	  --release

# ── Versioning ────────────────────────────────────────────────────────────────
# Convención semántica de RiskRunner:
#   PATCH → bug fix, visual tweak, texto
#   MINOR → nueva mecánica, pantalla nueva, feature significativa
#   MAJOR → cambio disruptivo en mecánica central del juego
#
# Uso:
#   make bump-patch   →  1.0.0+1 → 1.0.1+2
#   make bump-minor   →  1.0.1+2 → 1.1.0+3
#   make bump-major   →  1.1.0+3 → 2.0.0+4

bump-patch:
	dart run scripts/bump_version.dart patch

bump-minor:
	dart run scripts/bump_version.dart minor

bump-major:
	dart run scripts/bump_version.dart major

# ── Release (merge develop → main, tag, build) ───────────────────────────────
# Uso típico:
#   make bump-patch   (o minor/major según lo que incluye el release)
#   git add pubspec.yaml && git commit -m "chore: bump version a $(VERSION)"
#   make release-ios

release-ios: _check-env _check-branch
	$(MAKE) tag-release
	$(MAKE) build-prod-ios

release-android: _check-env _check-branch
	$(MAKE) tag-release
	$(MAKE) build-prod-android

# Guards internos
_check-env:
	@git diff --cached --name-only | grep -q "env.dart" \
	  && echo "BLOQUEADO: env.dart está staged. Abortar." && exit 1 || true
	@git diff --name-only | grep -q "env.dart" \
	  && echo "AVISO: env.dart aparece en diff (skip-worktree activo — ok si intencional)" || true

_check-branch:
	@current=$$(git branch --show-current); \
	if [ "$$current" != "main" ] && echo "$$current" | grep -qv "^release/"; then \
	  echo "AVISO: estás en '$$current', no en main ni release/x.x.x. Continuar solo si es intencional."; \
	fi

tag-release:
	git tag -a "v$(shell echo $(VERSION) | cut -d+ -f1)" -m "Release $(VERSION)"
	@echo "Tag creado. Ejecuta: git push origin v$(shell echo $(VERSION) | cut -d+ -f1)"

# ── Tests ─────────────────────────────────────────────────────────────────────
test:
	flutter test

test-coverage:
	flutter test --coverage
	genhtml coverage/lcov.info -o coverage/html
	@echo "Abre coverage/html/index.html"

analyze:
	flutter analyze

# ── Utilidades ────────────────────────────────────────────────────────────────
clean:
	flutter clean && flutter pub get

icons:
	dart run flutter_launcher_icons

.PHONY: run-dev run-dev-android build-staging-ios build-staging-android \
        build-prod-ios build-prod-android \
        bump-patch bump-minor bump-major \
        release-ios release-android _check-env _check-branch tag-release \
        test test-coverage analyze clean icons
