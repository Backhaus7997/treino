import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — detector de spacing FUERA de la escala
/// `8 · 12 · 14 · 18 · 20` (+ `4` como hairline).
///
/// Cuarto guard de la familia, después de `no_hex_scan_test.dart` (color),
/// `no_raw_radius_scan_test.dart` (radios) y `no_raw_font_size_scan_test.dart`
/// (tipografía).
///
/// EL ESTADO AL CONGELAR (medido sobre `main` a `f86a0b5b`, 2026-09-07):
/// **982 valores fuera de escala en 166 archivos**. Los tres más usados son
/// `16` (192), `10` (186) y `24` (180) — y `16` y `24` son los dos que
/// `AGENTS.md` §2 prohíbe **por nombre**: «Spacing: sólo `8 · 12 · 14 · 18 ·
/// 20` px. No 16/24». 372 ocurrencias de una regla escrita en la constitución
/// del repo y sin nadie que la mirara.
///
/// QUÉ MIRA, Y QUÉ NO — la diferencia con los otros tres guards:
///
/// Los otros prohíben el **literal** (`Radius.circular(16)` está mal aunque 16
/// sea `AppRadius.md`, porque el objetivo es que se use el token). Este
/// prohíbe el **valor**. `SizedBox(height: 8)` pasa: cumple la regla tal como
/// está escrita. Usar `AppSpacing.s8` es mejor y se recomienda, pero exigirlo
/// sería inventar una regla más estricta que la que el proyecto acordó, y
/// convertiría 1407 usos correctos en deuda.
///
/// Lo que este guard persigue es el daño real: el `16` y el `24` que se
/// cuelan, no el `8` escrito a mano.
///
/// ALCANCE DEL SCANNER (deliberado):
///   ✓ SizedBox(height: 16)                — separador
///   ✓ EdgeInsets.all(24)                  — padding
///   ✓ EdgeInsets.fromLTRB(24, 20, 24, 24) — cada argumento por separado
///   ✗ SizedBox(height: 8)                 — en escala
///   ✗ SizedBox(width: 420)                — >40px: eso es LAYOUT, no spacing.
///                                           Un panel de 420 no es un gutter.
///   ✗ EdgeInsets.all(AppSpacing.s8)       — token
///   ✗ EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom)
///                                         — el regex no entra en paréntesis
///                                           anidados, a propósito
///
/// HAY FALSOS POSITIVOS, Y ESTÁ BIEN. Un `EdgeInsets.only(bottom: 96)` para
/// despejar la bottom bar es layout, no spacing; los `1`, `2` y `3` sueltos
/// suelen ser filetes. Igual que la cola de la burbuja de chat en el guard de
/// radios, entran a la allowlist como deuda registrada: el guard congela el
/// estado y sólo se puede achicar, así que un falso positivo cuesta una línea
/// en la lista, no una migración forzada.
///
/// CUATRO REGLAS (heredadas de `no_raw_radius_scan_test.dart`):
///   1. Ningún archivo FUERA de la allowlist puede tener spacing fuera de escala.
///   2. La allowlist NUNCA crece — ratchet de archivos.
///   3. La deuda total NUNCA crece — ratchet de ocurrencias.
///   4. Un archivo que ya no tiene deuda DEBE salir de la allowlist.
///
/// Para pedir una excepción, ver `docs/design-system.md` → "Excepciones a la
/// escala de spacing".
void main() {
  group('no_off_scale_spacing_scan — spacing fuera de 8·12·14·18·20', () {
    /// La escala oficial (`AGENTS.md` §2 / `docs/design-system.md`), más `4`
    /// (`AppSpacing.hairline`) y `0`, que es ausencia de espacio y no un valor
    /// de la escala.
    // `final` y no `const`: Dart no admite un `const Set<double>` porque los
    // doubles no tienen igualdad primitiva.
    final scale = <double>{0, 4, 8, 12, 14, 18, 20};

    /// Separadores: `SizedBox` de una sola dimensión. El corte en 40px separa
    /// spacing de layout — ver el dartdoc de arriba.
    final sizedBoxPattern = RegExp(
      r'SizedBox\(\s*(?:height|width):\s*([0-9]+(?:\.[0-9]+)?)\s*[,)]',
    );
    const sizedBoxSpacingCeiling = 40.0;

    /// Padding: el cuerpo del `EdgeInsets`, sin paréntesis anidados.
    final edgeInsetsPattern = RegExp(
      r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(([^()]*)\)',
    );

    /// Literales numéricos sueltos dentro del cuerpo de un `EdgeInsets`. Los
    /// look-arounds evitan matchear la parte numérica de un identificador
    /// (`s8`, `AppSpacing.s12`).
    final numberPattern = RegExp(r'(?<![\w.])([0-9]+(?:\.[0-9]+)?)(?![\w.])');

    /// Techo de archivos permitidos, congelado con el PR que trae el guard.
    /// NUNCA subirlo.
    const allowlistCeiling = 166;

    /// Techo de ocurrencias totales en `lib/`. Mismo contrato: sólo baja.
    const offScaleDebtCeiling = 982;

    /// Allowlist de rutas relativas a `lib/` con spacing fuera de escala. Es
    /// un REGISTRO DE DEUDA, no una licencia.
    const allowlist = {
      'app/not_found_screen.dart',
      'app/router.dart',
      'core/widgets/firebase_storage_video_player.dart',
      'core/widgets/treino_bottom_bar.dart',
      'features/auth/presentation/forgot_password_screen.dart',
      'features/auth/presentation/legal/legal_document_screen.dart',
      'features/auth/presentation/profile_unavailable_screen.dart',
      'features/auth/presentation/register_screen.dart',
      'features/auth/presentation/splash_screen.dart',
      'features/auth/presentation/welcome_screen.dart',
      'features/auth/presentation/widgets/auth_pill_button.dart',
      'features/auth/presentation/widgets/password_strength_bar.dart',
      'features/auth/presentation/widgets/trainer_inquiry_card.dart',
      'features/chat/presentation/chat_image_bubble.dart',
      'features/chat/presentation/chat_list_screen.dart',
      'features/chat/presentation/chat_video_bubble.dart',
      'features/checkins/presentation/wellbeing_check_in_sheet.dart',
      'features/coach/athlete_coach_view.dart',
      'features/coach/presentation/athlete_agenda_screen.dart',
      'features/coach/presentation/athlete_detail_screen.dart',
      'features/coach/presentation/availability_editor_screen.dart',
      'features/coach/presentation/trainer_agenda_tab.dart',
      'features/coach/presentation/trainer_dashboard_tab.dart',
      'features/coach/presentation/trainer_public_profile_screen.dart',
      'features/coach/presentation/trainers_list_screen.dart',
      'features/coach/presentation/widgets/appointment_detail_sheet.dart',
      'features/coach/presentation/widgets/athlete_picker_sheet.dart',
      'features/coach/presentation/widgets/day_slots_sheet.dart',
      'features/coach/presentation/widgets/day_timeline.dart',
      'features/coach/presentation/widgets/equipment_filter_sheet.dart',
      'features/coach/presentation/widgets/exercise_picker_sheet.dart',
      'features/coach/presentation/widgets/invite_dialog.dart',
      'features/coach/presentation/widgets/location_permission_rationale_sheet.dart',
      'features/coach/presentation/widgets/muscle_filter_sheet.dart',
      'features/coach/presentation/widgets/new_session_sheet.dart',
      'features/coach/presentation/widgets/session_detail_sheet.dart',
      'features/coach/presentation/widgets/trainer_compact_filter_row.dart',
      'features/coach/presentation/widgets/trainer_contact_cta_stub.dart',
      'features/coach/presentation/widgets/trainer_day_detail_sheet.dart',
      'features/coach/presentation/widgets/trainer_inquiry_cta.dart',
      'features/coach/presentation/widgets/trainer_list_tile.dart',
      'features/coach/presentation/widgets/trainer_profile_hero.dart',
      'features/coach/presentation/widgets/trainer_specialty_chips.dart',
      'features/coach/presentation/widgets/trainers_map_bottom_sheet.dart',
      'features/coach/presentation/widgets/trainers_map_view.dart',
      'features/coach/trainer_coach_view.dart',
      'features/coach_hub/presentation/coach_hub_not_allowed_screen.dart',
      'features/coach_hub/presentation/coach_hub_plan_preview_screen.dart',
      'features/coach_hub/presentation/coach_hub_upload_plan_screen.dart',
      'features/coach_hub/presentation/sections/agenda/agenda_time_grid.dart',
      'features/coach_hub/presentation/sections/agenda/agenda_web_calendar.dart',
      'features/coach_hub/presentation/sections/agenda/agenda_web_day_list.dart',
      'features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart',
      'features/coach_hub/presentation/sections/agenda/appointment_detail_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/availability_editor_panel.dart',
      'features/coach_hub/presentation/sections/agenda/batch_cobrar_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/new_session_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/override_form_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/rule_form_dialog.dart',
      'features/coach_hub/presentation/sections/ajustes/ajustes_screen.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_tab.dart',
      'features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart',
      'features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/ejercicios_tab.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/template_detail_dialog.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/templates_tab.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_detail_pane.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_list_pane.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/blocked_students_screen.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/keep_students_screen.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/paywall_preview_screen.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart',
      'features/coach_hub/presentation/sections/invitaciones/widgets/solicitud_card.dart',
      'features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/estado_cuenta_card.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart',
      'features/coach_hub/presentation/sections/perfil_publico/widgets/especialidad_precio_card.dart',
      'features/coach_hub/presentation/sections/perfil_publico/widgets/identidad_card.dart',
      'features/coach_hub/presentation/sections/planes/planes_screen.dart',
      'features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart',
      'features/coach_hub/presentation/sections/rutinas/athlete_routines_screen.dart',
      'features/coach_hub/presentation/sections/rutinas/rutinas_screen.dart',
      'features/coach_hub/presentation/shell/coach_hub_sidebar.dart',
      'features/coach_hub/presentation/widgets/create_custom_exercise_dialog.dart',
      'features/coach_hub/presentation/widgets/exercise_picker_dialog.dart',
      'features/coach_hub/presentation/widgets/preview_wrapper.dart',
      'features/feed/feed_screen.dart',
      'features/feed/presentation/create_post_screen.dart',
      'features/feed/presentation/public_profile_screen.dart',
      'features/feed/presentation/widgets/friend_request_inbox_tile.dart',
      'features/feed/presentation/widgets/user_search_result_tile.dart',
      'features/gym_rankings/presentation/rankings_screen.dart',
      'features/home/home_screen.dart',
      'features/home/widgets/esta_semana_card.dart',
      'features/insights/presentation/insights_screen.dart',
      'features/insights/presentation/widgets/day_strip_navigator.dart',
      'features/insights/presentation/widgets/monthly_report_chart.dart',
      'features/insights/presentation/widgets/monthly_report_summary_cards.dart',
      'features/insights/presentation/widgets/muscle_distribution_radar.dart',
      'features/insights/presentation/widgets/workout_days_calendar.dart',
      'features/measurements/presentation/log_measurement_screen.dart',
      'features/measurements/presentation/widgets/measurement_history_list.dart',
      'features/measurements/presentation/widgets/measurement_progress_chart.dart',
      'features/onboarding/presentation/custom_exercise_onboarding_art.dart',
      'features/onboarding/presentation/onboarding_chrome.dart',
      'features/onboarding/presentation/onboarding_flow.dart',
      'features/onboarding/presentation/onboarding_illustration.dart',
      'features/onboarding/presentation/onboarding_previews.dart',
      'features/onboarding/presentation/onboarding_tour_view.dart',
      'features/onboarding/presentation/trainer_previews.dart',
      'features/onboarding/presentation/widgets/onboarding_device_preview.dart',
      'features/onboarding/presentation/widgets/onboarding_nav_bar.dart',
      'features/onboarding/presentation/widgets/onboarding_preview_cards.dart',
      'features/onboarding/presentation/widgets/trainer_preview_kit.dart',
      'features/performance/presentation/log_performance_test_screen.dart',
      'features/performance/presentation/widgets/performance_progress_chart.dart',
      'features/profile/presentation/profile_edit_personal_screen.dart',
      'features/profile/presentation/profile_edit_trainer_screen.dart',
      'features/profile/presentation/profile_routines_screen.dart',
      'features/profile/presentation/widgets/nearby_gyms_list.dart',
      'features/profile/presentation/widgets/profile_avatar_card.dart',
      'features/profile/presentation/widgets/profile_section_group.dart',
      'features/profile/presentation/widgets/profile_section_tile.dart',
      'features/profile/presentation/widgets/profile_trainer_section.dart',
      'features/profile/profile_screen.dart',
      'features/profile/trainer_profile_view.dart',
      'features/profile_setup/presentation/steps/step_1_username_avatar.dart',
      'features/profile_setup/presentation/widgets/gym_card.dart',
      'features/profile_setup/presentation/widgets/gym_search_box.dart',
      'features/profile_setup/presentation/widgets/profile_setup_header.dart',
      'features/reviews/presentation/widgets/review_bottom_sheet.dart',
      'features/reviews/presentation/widgets/review_cta.dart',
      'features/reviews/presentation/widgets/review_tile.dart',
      'features/reviews/presentation/widgets/star_rating_display.dart',
      'features/workout/presentation/custom_exercise_editor_screen.dart',
      'features/workout/presentation/exercise_detail_screen.dart',
      'features/workout/presentation/my_exercises_screen.dart',
      'features/workout/presentation/post_workout_summary_screen.dart',
      'features/workout/presentation/routine_detail_screen.dart',
      'features/workout/presentation/routine_editor_screen.dart',
      'features/workout/presentation/session_detail_screen.dart',
      'features/workout/presentation/session_history_screen.dart',
      'features/workout/presentation/session_player_screen.dart',
      'features/workout/presentation/share_workout_composer_screen.dart',
      'features/workout/presentation/widgets/coach_chip.dart',
      'features/workout/presentation/widgets/duration_set_row.dart',
      'features/workout/presentation/widgets/exercise_progression_chart.dart',
      'features/workout/presentation/widgets/exercise_progression_section.dart',
      'features/workout/presentation/widgets/exercise_slot_row.dart',
      'features/workout/presentation/widgets/historial_section.dart',
      'features/workout/presentation/widgets/most_frequent_exercises_list.dart',
      'features/workout/presentation/widgets/personal_records_list.dart',
      'features/workout/presentation/widgets/premium_chip.dart',
      'features/workout/presentation/widgets/routine_card.dart',
      'features/workout/presentation/widgets/rutinas_section.dart',
      'features/workout/presentation/widgets/session_exercise_block.dart',
      'features/workout/presentation/widgets/session_highlights_section.dart',
      'features/workout/presentation/widgets/set_entry_sheet.dart',
      'features/workout/presentation/widgets/template_ratings_section.dart',
      'features/workout/trainer_workout_view.dart',
      'features/workout/workout_screen.dart',
      'main_wear_liveness_spike.dart',
    };

    /// Cuenta los valores fuera de escala de un archivo.
    int offScaleIn(String source) {
      var count = 0;
      for (final m in sizedBoxPattern.allMatches(source)) {
        final v = double.parse(m.group(1)!);
        if (v <= sizedBoxSpacingCeiling && !scale.contains(v)) count++;
      }
      for (final m in edgeInsetsPattern.allMatches(source)) {
        for (final n in numberPattern.allMatches(m.group(1)!)) {
          if (!scale.contains(double.parse(n.group(1)!))) count++;
        }
      }
      return count;
    }

    late List<String> offenders;
    late List<String> staleEntries;
    late int totalDebt;

    setUpAll(() {
      final libDir = Directory('lib');
      offenders = [];
      staleEntries = [];
      totalDebt = 0;

      if (!libDir.existsSync()) {
        // Corriendo desde otro directorio: los expects fallan con mensaje claro.
        staleEntries = allowlist.toList()..sort();
        return;
      }

      final seen = <String>{};

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        // Normalizar separadores a slash para comparación cross-platform.
        final normalized = entity.path.replaceAll(r'\', '/');
        final libIndex = normalized.indexOf('lib/');
        if (libIndex == -1) continue;
        final relativePath = normalized.substring(libIndex + 4); // tras "lib/"

        final matches = offScaleIn(entity.readAsStringSync());
        totalDebt += matches;

        if (matches == 0) continue;
        seen.add(relativePath);
        if (!allowlist.contains(relativePath)) offenders.add(relativePath);
      }

      offenders.sort();
      staleEntries = allowlist.where((p) => !seen.contains(p)).toList()..sort();
    });

    test('ningún archivo fuera de la allowlist usa spacing fuera de escala',
        () {
      expect(
        offenders,
        isEmpty,
        reason: 'Spacing fuera de escala en archivos no listados:\n'
            '${offenders.join('\n')}\n\n'
            'La escala es 8 · 12 · 14 · 18 · 20 (AGENTS.md §2), más 4 como\n'
            'hairline para gutters internos de un componente. 16 y 24 están\n'
            'prohibidos POR NOMBRE — son los dos que más se cuelan.\n\n'
            '  SizedBox(height: 16)  →  SizedBox(height: AppSpacing.s14)  (o s18)\n'
            '  EdgeInsets.all(24)    →  EdgeInsets.all(AppSpacing.s20)\n\n'
            'Si tu valor es LAYOUT y no spacing (el ancho de un panel, el\n'
            'despeje de la bottom bar), sacalo del EdgeInsets a una constante\n'
            'con nombre: deja de contar y además dice qué es.',
      );
    });

    test('la allowlist no creció vs el estado congelado (ratchet de archivos)',
        () {
      expect(
        allowlist.length,
        lessThanOrEqualTo(allowlistCeiling),
        reason: 'La allowlist tiene ${allowlist.length} entradas y el techo es '
            '$allowlistCeiling. SÓLO PUEDE ACHICARSE. Si migraste archivos, '
            'bajá también allowlistCeiling a ${allowlist.length}.',
      );
    });

    test('la deuda total no creció (ratchet de ocurrencias)', () {
      expect(
        totalDebt,
        lessThanOrEqualTo(offScaleDebtCeiling),
        reason: 'Hay $totalDebt valores fuera de escala en lib/ y el techo es '
            '$offScaleDebtCeiling. Agregar uno a un archivo YA listado también '
            'rompe el ratchet: sin esta regla, 166 archivos podrían sumar '
            'deuda en silencio. Migrá a la escala en vez de subir el techo.',
      );
    });

    test('la allowlist no tiene entradas muertas', () {
      expect(
        staleEntries,
        isEmpty,
        reason: 'Estos archivos ya no tienen spacing fuera de escala (o no '
            'existen) pero siguen en la allowlist:\n${staleEntries.join('\n')}'
            '\n\nSacalos y bajá allowlistCeiling. El registro de deuda tiene '
            'que reflejar la deuda real.',
      );
    });
  });
}
