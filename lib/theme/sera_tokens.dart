// sera_tokens.dart
// ─────────────────────────────────────────────────────────────────────────
// SERA design tokens — generated from the design system (colors_and_type.css).
// Drop this into lib/theme/ and import it anywhere you need a brand value.
// This is the single source of truth: replace scattered hex literals with
// SeraTokens.* references so a token change propagates app-wide.
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class SeraTokens {
  SeraTokens._();

  // ── Brand / primary ─────────────────────────────────────────────────────
  static const primary       = Color(0xFF188BFF);
  static const primaryDark    = Color(0xFF0A6FE8);
  static const primaryDeep    = Color(0xFF0A5FC4);
  static const primaryLight   = Color(0xFFDCEEFF);
  static const accent         = Color(0xFF40A9FF);

  // ── Neutral surfaces ────────────────────────────────────────────────────
  static const surface        = Color(0xFFF4F7FF);
  static const surfaceCard     = Color(0xFFFFFFFF);
  static const surfaceTint      = Color(0xFFF7FAFF);
  static const surfaceBlue      = Color(0xFFF0F7FF);
  static const deepNavy         = Color(0xFF050F1A);

  // ── Text / foreground ───────────────────────────────────────────────────
  static const fg1            = Color(0xFF0D1B2A);
  static const fg1Alt          = Color(0xFF1A2B3C);
  static const fg2             = Color(0xFF5A6A7E);
  static const fg3             = Color(0xFF6B7A8D);
  static const muted           = Color(0xFF8896A5);
  static const hint            = Color(0xFFAFBDCC);
  static const disabled        = Color(0xFFCBD5E1);

  // ── Borders / dividers ──────────────────────────────────────────────────
  static const borderStrong   = Color(0xFFD8E4F0);
  static const border          = Color(0xFFE8EDF5);
  static const borderSoft       = Color(0xFFE0E8F0);
  static const divider          = Color(0xFFF0F3F8);
  static const borderBlue       = Color(0xFFD0E4FF);
  static const borderField      = Color(0xFFD8E8FF); // settings form field outline

  // ── Status (BRD / PRD pipeline) ─────────────────────────────────────────
  static const statusDraft           = Color(0xFF78909C);
  static const statusInProgress       = Color(0xFF1565C0);
  static const statusInProgressWarm    = Color(0xFFFF8F00);
  static const statusPendingReview     = Color(0xFF6A1B9A);
  static const statusInReview          = Color(0xFF1E88E5);
  static const statusChanges           = Color(0xFFE53935);
  static const statusApproved          = Color(0xFF43A047);
  static const statusSent              = Color(0xFF00897B);
  // Dashboard status-meta variants (the home tab uses a slightly different set)
  static const statusInReviewAlt       = Color(0xFF8E24AA); // "In Review" tile
  static const statusInfo              = Color(0xFF1E88E5); // "Pending Review" tile / action-needed
  static const accentOrange            = Color(0xFFE65100); // PRD generate-prompt accent
  static const iconInactive            = Color(0xFFB0BEC5); // inactive step dots / delete icon

  // ── Priority ────────────────────────────────────────────────────────────
  static const priorityLow      = Color(0xFF4CAF50);
  static const priorityMedium    = Color(0xFF2196F3);
  static const priorityHigh      = Color(0xFFFF9800);
  static const priorityCritical  = Color(0xFFF44336);

  // ── Feedback ────────────────────────────────────────────────────────────
  static const error          = Color(0xFFEF4444);
  static const errorText       = Color(0xFFB91C1C);
  static const errorBg         = Color(0xFFFFF2F2);
  static const errorBorder     = Color(0xFFFFCDD2);

  // ── Radii ───────────────────────────────────────────────────────────────
  static const rXs = 6.0, rSm = 8.0, rMd = 10.0, rLg = 12.0,
               rXl = 14.0, r2xl = 16.0, r3xl = 18.0, rPill = 20.0,
               rLogo = 22.0, rHero = 32.0;

  // ── Signature gradients ─────────────────────────────────────────────────
  // Hero: login header, welcome banner, splash orb.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF04111F), Color(0xFF0A3468), Color(0xFF0D6FD8)],
    stops: [0.0, 0.5, 1.0],
  );
  // Primary button.
  static const buttonGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF188BFF), Color(0xFF0A6FE8)],
  );

  // ── Shadows ─────────────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: const Color(0xFF0D1B2A).withValues(alpha: 0.03),
            blurRadius: 8, offset: const Offset(0, 2)),
      ];
  static List<BoxShadow> get statShadow => [
        BoxShadow(color: primary.withValues(alpha: 0.08),
            blurRadius: 12, offset: const Offset(0, 4)),
      ];
  static List<BoxShadow> get buttonGlow => [
        BoxShadow(color: primary.withValues(alpha: 0.30),
            blurRadius: 16, offset: const Offset(0, 6)),
      ];
  static List<BoxShadow> get bannerGlow => [
        BoxShadow(color: primary.withValues(alpha: 0.22),
            blurRadius: 20, offset: const Offset(0, 8)),
      ];

  // ── Fixed status → color map (mirror notes_screen.dart) ─────────────────
  static const statusColors = <String, Color>{
    'Draft': statusDraft,
    'In Progress': statusInProgress,
    'Pending Review': statusPendingReview,
    'In Review': statusInReview,
    'Changes Requested': statusChanges,
    'Approved': statusApproved,
  };
}
