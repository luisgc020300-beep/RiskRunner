// lib/widgets/app_button.dart
//
// Botón único de RiskRunner. Tres variantes: primary, secondary, ghost.
// Sustituye todos los GestureDetector+Container de botón dispersos en la app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, ghost }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;
  final Color? color;       // sobreescribe el color de acento si se necesita
  final double? fontSize;

  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
    this.color,
    this.fontSize,
  });

  // ── Constructores semánticos ─────────────────────────────────────────────────

  const AppButton.primary({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
    this.color,
    this.fontSize,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
    this.color,
    this.fontSize,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
    this.color,
    this.fontSize,
  }) : variant = AppButtonVariant.ghost;

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.red;

    final Color bgColor = switch (variant) {
      AppButtonVariant.primary   => accent,
      AppButtonVariant.secondary => Colors.transparent,
      AppButtonVariant.ghost     => Colors.transparent,
    };

    final Color textColor = switch (variant) {
      AppButtonVariant.primary   => AppColors.textPrimary,
      AppButtonVariant.secondary => accent,
      AppButtonVariant.ghost     => AppColors.textTertiary,
    };

    final Border? border = switch (variant) {
      AppButtonVariant.primary   => null,
      AppButtonVariant.secondary => Border.all(color: accent, width: AppTokens.borderNormal),
      AppButtonVariant.ghost     => null,
    };

    final content = loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(textColor),
            ),
          )
        : Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: textColor, size: AppTokens.iconSm),
                const SizedBox(width: AppTokens.spaceXs),
              ],
              Text(
                label,
                style: AppTypography.label(textColor, size: fontSize),
              ),
            ],
          );

    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      border: border,
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        onTap: (onTap == null || loading)
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onTap!();
              },
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        splashColor: accent.withValues(alpha: 0.15),
        highlightColor: accent.withValues(alpha: 0.08),
        child: Ink(
          decoration: decoration,
          child: Container(
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(
              vertical: AppTokens.spaceSm + 2,   // 10px
              horizontal: AppTokens.spaceMd,
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}
