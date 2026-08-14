import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — detector de radios crudos fuera de `AppRadius`.
///
/// Contraparte de `no_hex_scan_test.dart` para la escala de radios.
/// `AppRadius` define cuatro valores (`sm` 12, `md` 16, `lg` 20, `full` 9999) y
/// `docs/design-system.md` los documenta como escala CERRADA. La adopción era
/// ~10%: al congelarse este guard, 668 literales `Radius.circular(N)` repartidos
/// en 149 archivos de `lib/`, contra ~71 usos de `AppRadius.*`. (La issue #665
/// midió 678 sobre `40445dc5`; #546 se llevó 10 en el medio. Los techos de abajo
/// son la cifra que vale: se miden contra el `main` del que sale esta rama.)
///
/// A diferencia del scanner de hex, acá NO se puede exigir cero de entrada.
/// Parte de esos literales son decisiones de diseño aprobadas que todavía no
/// tienen token propio — por ejemplo la cola asimétrica de la burbuja de chat
/// (14/14/14/4), que viene del mockup de #339. Barrerlos automáticamente
/// cambiaría un diseño aprobado. Por eso el guard congela el estado actual y
/// sólo se puede achicar.
///
/// CUATRO REGLAS (issue #665):
///   1. Ningún archivo FUERA de la allowlist puede contener un radio crudo.
///   2. La allowlist NUNCA crece — ratchet de archivos.
///   3. La deuda total NUNCA crece — ratchet de ocurrencias.
///   4. Un archivo que ya no tiene radios crudos DEBE salir de la allowlist.
///
/// La regla 3 es la que falta en el scanner de hex y la que explica cómo se
/// acumularon los 678: un archivo ya listado podía sumar radios crudos sin que
/// nadie lo viera. Con el techo de deuda, agregar uno obliga a migrar otro.
///
/// ALCANCE DEL SCANNER (deliberado):
///   ✓ Radius.circular(20)          — literal numérico
///   ✓ BorderRadius.circular(20)    — el patrón matchea como sufijo
///   ✗ circular(AppRadius.lg)       — referencia a token; es exactamente el objetivo
///   ✗ circular(TreinoCardTokens.borderRadius) — token de componente (capa 3)
///   ✗ circular(_kPillRadius)       — literal lavado por una const intermedia.
///                                    El scanner no lo ve, igual que el de hex
///                                    no ve `Colors.*`. Eso se caza en review.
///
/// Para pedir una excepción, ver `docs/design-system.md` → "Excepciones a la
/// escala de radios".
void main() {
  group('no_raw_radius_scan — prohibición de Radius.circular(<literal>)', () {
    /// Detecta `Radius.circular(<literal>)` y, por sufijo, también
    /// `BorderRadius.circular(<literal>)`. Sólo literales numéricos: cualquier
    /// referencia a una constante o expresión queda fuera a propósito.
    final rawRadiusPattern = RegExp(
      r'Radius\.circular\(\s*[0-9]+(?:\.[0-9]+)?\s*\)',
    );

    /// Techo de archivos permitidos. Congelado en el estado de `main` al abrir
    /// la issue #665. NUNCA subir este número: cada fase que migra un archivo
    /// lo baja.
    const allowlistCeiling = 121;

    /// Techo de ocurrencias totales de radio crudo en `lib/`. Mismo contrato
    /// que [allowlistCeiling]: sólo baja.
    const rawRadiusDebtCeiling = 390;

    /// Allowlist de rutas relativas a `lib/` que todavía contienen radios
    /// crudos. Es un REGISTRO DE DEUDA, no una licencia: estar acá significa
    /// "pendiente de migrar", no "exento".
    const allowlist = {
      'app/theme/app_theme.dart',
      'core/widgets/firebase_storage_video_player.dart',
      'core/widgets/treino_bottom_bar.dart',
      'features/auth/presentation/widgets/password_strength_bar.dart',
      'features/chat/presentation/chat_screen.dart',
      'features/checkins/presentation/post_session_check_in_sheet.dart',
      'features/coach/athlete_coach_view.dart',
      'features/coach/presentation/athlete_agenda_screen.dart',
      'features/coach/presentation/athlete_detail_screen.dart',
      'features/coach/presentation/availability_editor_screen.dart',
      'features/coach/presentation/trainer_dashboard_tab.dart',
      'features/coach/presentation/widgets/appointment_detail_sheet.dart',
      'features/coach/presentation/widgets/athlete_picker_sheet.dart',
      'features/coach/presentation/widgets/day_slots_sheet.dart',
      'features/coach/presentation/widgets/day_timeline.dart',
      'features/coach/presentation/widgets/equipment_filter_sheet.dart',
      'features/coach/presentation/widgets/exercise_picker_sheet.dart',
      'features/coach/presentation/widgets/location_permission_rationale_sheet.dart',
      'features/coach/presentation/widgets/muscle_filter_sheet.dart',
      'features/coach/presentation/widgets/new_session_sheet.dart',
      'features/coach/presentation/widgets/session_detail_sheet.dart',
      'features/coach/presentation/widgets/trainer_advanced_filter_chips.dart',
      'features/coach/presentation/widgets/trainer_day_detail_sheet.dart',
      'features/coach/presentation/widgets/trainers_map_bottom_sheet.dart',
      'features/coach/presentation/widgets/trainers_map_view.dart',
      'features/coach/trainer_coach_view.dart',
      'features/coach_hub/presentation/coach_hub_login_screen.dart',
      'features/coach_hub/presentation/coach_hub_plan_preview_screen.dart',
      'features/coach_hub/presentation/coach_hub_upload_plan_screen.dart',
      'features/coach_hub/presentation/sections/agenda/agenda_web_day_list.dart',
      'features/coach_hub/presentation/sections/agenda/appointment_detail_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/override_form_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/rule_form_dialog.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_tab.dart',
      'features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart',
      'features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/template_detail_dialog.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/templates_tab.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_list_pane.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/paywall_preview_screen.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart',
      'features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart',
      'features/coach_hub/presentation/sections/rutinas/rutinas_screen.dart',
      'features/coach_hub/presentation/widgets/create_custom_exercise_dialog.dart',
      'features/coach_hub/presentation/widgets/data_table/coach_hub_data_table.dart',
      'features/coach_hub/presentation/widgets/dialog/treino_dialog.dart',
      'features/coach_hub/presentation/widgets/empty_state/empty_state.dart',
      'features/coach_hub/presentation/widgets/exercise_picker_dialog.dart',
      'features/feed/feed_screen.dart',
      'features/feed/presentation/create_post_screen.dart',
      'features/feed/presentation/widgets/friend_request_inbox_tile.dart',
      'features/feed/presentation/widgets/suggested_users_section.dart',
      'features/feed/presentation/widgets/unfriend_confirmation_sheet.dart',
      'features/feed/presentation/widgets/user_search_result_tile.dart',
      'features/feed/presentation/widgets/workout_snapshot_detail.dart',
      'features/gym_rankings/presentation/rankings_screen.dart',
      'features/home/home_screen.dart',
      'features/home/widgets/empezar_entrenamiento_card.dart',
      'features/home/widgets/esta_semana_card.dart',
      'features/insights/presentation/insights_screen.dart',
      'features/insights/presentation/measurements_screen.dart',
      'features/insights/presentation/monthly_report_screen.dart',
      'features/insights/presentation/muscle_distribution_screen.dart',
      'features/insights/presentation/volume_by_group_screen.dart',
      'features/insights/presentation/widgets/body_silhouette_placeholder.dart',
      'features/insights/presentation/widgets/daily_heatmap_section.dart',
      'features/insights/presentation/widgets/monthly_report_chart.dart',
      'features/insights/presentation/widgets/monthly_report_summary_cards.dart',
      'features/insights/presentation/widgets/muscle_distribution_radar.dart',
      'features/insights/presentation/widgets/workout_days_calendar.dart',
      'features/measurements/presentation/log_measurement_screen.dart',
      'features/measurements/presentation/widgets/measurement_history_list.dart',
      'features/measurements/presentation/widgets/measurement_progress_chart.dart',
      'features/performance/presentation/log_performance_test_screen.dart',
      'features/performance/presentation/widgets/performance_progress_chart.dart',
      'features/profile/presentation/appearance_screen.dart',
      'features/profile/presentation/profile_edit_trainer_screen.dart',
      'features/profile/presentation/profile_gym_screen.dart',
      'features/profile/presentation/widgets/eliminar_cuenta_sheet.dart',
      'features/profile/presentation/widgets/profile_avatar_card.dart',
      'features/profile/presentation/widgets/profile_section_group.dart',
      'features/profile/presentation/widgets/profile_section_tile.dart',
      'features/profile/presentation/widgets/re_auth_bottom_sheet.dart',
      'features/profile/profile_screen.dart',
      'features/profile/trainer_profile_view.dart',
      'features/profile_setup/presentation/widgets/experience_card.dart',
      'features/profile_setup/presentation/widgets/gender_chip.dart',
      'features/profile_setup/presentation/widgets/gym_card.dart',
      'features/profile_setup/presentation/widgets/profile_setup_header.dart',
      'features/reviews/presentation/widgets/review_bottom_sheet.dart',
      'features/reviews/presentation/widgets/review_cta.dart',
      'features/workout/presentation/custom_exercise_editor_screen.dart',
      'features/workout/presentation/exercise_detail_screen.dart',
      'features/workout/presentation/my_exercises_screen.dart',
      'features/workout/presentation/routine_detail_screen.dart',
      'features/workout/presentation/routine_editor_screen.dart',
      'features/workout/presentation/session_player_screen.dart',
      'features/workout/presentation/share_workout_composer_screen.dart',
      'features/workout/presentation/widgets/coach_chip.dart',
      'features/workout/presentation/widgets/coach_note.dart',
      'features/workout/presentation/widgets/exercise_progression_chart.dart',
      'features/workout/presentation/widgets/exercise_progression_section.dart',
      'features/workout/presentation/widgets/exercise_slot_row.dart',
      'features/workout/presentation/widgets/exercise_video_player.dart',
      'features/workout/presentation/widgets/level_filter_pills.dart',
      'features/workout/presentation/widgets/most_frequent_exercises_list.dart',
      'features/workout/presentation/widgets/personal_records_list.dart',
      'features/workout/presentation/widgets/resume_session_modal.dart',
      'features/workout/presentation/widgets/routine_card.dart',
      'features/workout/presentation/widgets/rutinas_section.dart',
      'features/workout/presentation/widgets/session_highlights_section.dart',
      'features/workout/presentation/widgets/session_stats_card.dart',
      'features/workout/presentation/widgets/set_entry_sheet.dart',
      'features/workout/presentation/widgets/template_rating_sheet.dart',
      'features/workout/trainer_workout_view.dart',
      'features/workout/workout_screen.dart',
    };

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

        final matches =
            rawRadiusPattern.allMatches(entity.readAsStringSync()).length;
        totalDebt += matches;

        if (matches == 0) continue;
        seen.add(relativePath);
        if (!allowlist.contains(relativePath)) offenders.add(relativePath);
      }

      offenders.sort();
      staleEntries = allowlist.where((p) => !seen.contains(p)).toList()..sort();
    });

    test('ningún archivo fuera de la allowlist usa Radius.circular(<literal>)',
        () {
      expect(
        offenders,
        isEmpty,
        reason: 'Radios crudos fuera de la allowlist:\n'
            '${offenders.join('\n')}\n\n'
            'Para corregir: usá la escala de AppRadius '
            '(sm 12 / md 16 / lg 20 / full 9999) en vez del literal.\n'
            '  BorderRadius.circular(16)  →  BorderRadius.circular(AppRadius.md)\n\n'
            'Si tu valor NO está en la escala, no lo agregues a la allowlist: '
            'seguí el proceso de excepción en docs/design-system.md → '
            '"Excepciones a la escala de radios".',
      );
    });

    test('la allowlist no creció vs el estado congelado (ratchet de archivos)',
        () {
      expect(
        allowlist.length,
        lessThanOrEqualTo(allowlistCeiling),
        reason: 'La allowlist tiene ${allowlist.length} entradas y el techo es '
            '$allowlistCeiling. La allowlist SÓLO PUEDE ACHICARSE. Si migraste '
            'archivos, bajá también allowlistCeiling a ${allowlist.length}.',
      );
    });

    test('la deuda total no creció (ratchet de ocurrencias)', () {
      expect(
        totalDebt,
        lessThanOrEqualTo(rawRadiusDebtCeiling),
        reason: 'Hay $totalDebt radios crudos en lib/ y el techo es '
            '$rawRadiusDebtCeiling. Agregar un radio crudo a un archivo YA '
            'listado también rompe el ratchet: por eso se acumularon 678 sin '
            'que nadie los viera. Migrá a AppRadius en vez de subir el techo.',
      );
    });

    test('la allowlist no tiene entradas muertas', () {
      expect(
        staleEntries,
        isEmpty,
        reason: 'Estos archivos ya no tienen radios crudos (o no existen) pero '
            'siguen en la allowlist:\n${staleEntries.join('\n')}\n\n'
            'Sacalos de la allowlist y bajá allowlistCeiling. El registro de '
            'deuda tiene que reflejar la deuda real.',
      );
    });
  });
}
