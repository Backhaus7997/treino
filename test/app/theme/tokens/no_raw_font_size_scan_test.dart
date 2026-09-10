import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — detector de `fontSize:` crudo fuera de
/// [AppTextSize].
///
/// Tercer guard de la familia, después de `no_hex_scan_test.dart` (color) y
/// `no_raw_radius_scan_test.dart` (radios). Mismo contrato de ratchet, misma
/// razón de existir — y esta dimensión es la que más lejos llegó sin uno.
///
/// EL ESTADO AL CONGELAR (medido sobre `main` a `f86a0b5b`, 2026-09-07):
/// **1879 `fontSize:` literales en 271 archivos, con 31 tamaños distintos**,
/// incluyendo `9.5`, `10.5`, `11.5`, `12.5`, `13.5` y `14.5`. Cero usos de
/// `Theme.of(context).textTheme`, que el tema sí define.
///
/// No fue descuido del equipo: color, spacing, radios, íconos y motion tienen
/// token Y guard, y se respetan con cero excepciones en todo el repo.
/// Tipografía era la única dimensión sin ninguno de los dos, y la deriva llenó
/// el hueco. `AppTextSize` (capa 1, junto a `AppSpacing` y `AppRadius`) es la
/// mitad que faltaba; este test es la otra.
///
/// Los techos de abajo ya descuentan la migración del kit compartido del Coach
/// Hub que entra en el mismo PR (54 ocurrencias, 11 archivos): se congela en
/// 1825/260, no en 1879/271. Congelar el número PRE-migración sería regalarse
/// margen.
///
/// CUATRO REGLAS (heredadas de `no_raw_radius_scan_test.dart`):
///   1. Ningún archivo FUERA de la allowlist puede tener un `fontSize` crudo.
///   2. La allowlist NUNCA crece — ratchet de archivos.
///   3. La deuda total NUNCA crece — ratchet de ocurrencias.
///   4. Un archivo que ya no tiene `fontSize` crudo DEBE salir de la allowlist.
///
/// La regla 3 es la que importa acá: con 260 archivos en la allowlist, sin
/// techo de ocurrencias cualquiera de ellos podría sumar diez `fontSize`
/// nuevos sin que ningún test se entere. Es exactamente así como se llegó a
/// 1879.
///
/// ALCANCE DEL SCANNER (deliberado):
///   ✓ fontSize: 14                    — literal numérico
///   ✓ fontSize: 12.5                  — medio píxel, que es deuda igual
///   ✓ GoogleFonts.barlow(fontSize: 16) — el patrón no mira el constructor
///   ✗ fontSize: AppTextSize.body       — token; es el objetivo
///   ✗ fontSize: _kHeroSize             — literal lavado por una const
///                                        intermedia. Igual que en los otros
///                                        dos scanners, eso se caza en review.
///
/// NO TODO LO QUE QUEDA ES DEUDA MIGRABLE. `AppTextSize` cubre 1609 de las
/// 1879 ocurrencias originales sin cambiar un píxel; el resto (`11` con 146
/// usos, `15` con 54, y los medios píxeles) migra al escalón más cercano y eso
/// SÍ mueve píxeles. Por eso el guard congela en vez de exigir cero: un barrido
/// automático cambiaría diseño aprobado sin que nadie lo mire. Y aparte están
/// los tamaños de ilustración de `onboarding/` —que dibujan la app en vez de
/// mostrarla, igual que `AppDecorativeRadii`— donde forzar la escala deforma el
/// dibujo.
///
/// Para pedir una excepción, ver `docs/design-system.md` → "Excepciones a la
/// escala tipográfica".
void main() {
  group('no_raw_font_size_scan — prohibición de fontSize: <literal>', () {
    /// Detecta `fontSize:` seguido de un literal numérico. El look-ahead
    /// negativo evita que `fontSize: 12` matchee el prefijo de `12.5` y lo
    /// cuente como entero.
    final rawFontSizePattern = RegExp(
      r'fontSize:\s*[0-9]+(?:\.[0-9]+)?(?![\d.])',
    );

    /// Techo de archivos permitidos, congelado con el PR que trae el guard.
    /// NUNCA subirlo: cada migración lo baja.
    const allowlistCeiling = 257;

    /// Techo de ocurrencias totales en `lib/`. Mismo contrato: sólo baja.
    const rawFontSizeDebtCeiling = 1775;

    /// Allowlist de rutas relativas a `lib/` que todavía tienen `fontSize`
    /// crudo. Es un REGISTRO DE DEUDA, no una licencia.
    const allowlist = {
      'app/not_found_screen.dart',
      'core/widgets/treino_bottom_bar.dart',
      'features/auth/presentation/forgot_password_screen.dart',
      'features/auth/presentation/legal/legal_document_screen.dart',
      'features/auth/presentation/login_screen.dart',
      'features/auth/presentation/profile_unavailable_screen.dart',
      'features/auth/presentation/register_screen.dart',
      'features/auth/presentation/splash_screen.dart',
      'features/auth/presentation/welcome_screen.dart',
      'features/auth/presentation/widgets/auth_input.dart',
      'features/auth/presentation/widgets/auth_pill_button.dart',
      'features/auth/presentation/widgets/auth_secondary_button.dart',
      'features/auth/presentation/widgets/password_strength_bar.dart',
      'features/auth/presentation/widgets/terms_checkbox.dart',
      'features/auth/presentation/widgets/terms_notice_text.dart',
      'features/auth/presentation/widgets/trainer_inquiry_card.dart',
      'features/chat/presentation/chat_image_bubble.dart',
      'features/chat/presentation/chat_list_screen.dart',
      'features/chat/presentation/chat_screen.dart',
      'features/chat/presentation/chat_video_bubble.dart',
      'features/checkins/presentation/wellbeing_check_in_sheet.dart',
      'features/checkins/presentation/widgets/wellbeing_mood_row.dart',
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
      'features/coach/presentation/widgets/trainer_advanced_filter_chips.dart',
      'features/coach/presentation/widgets/trainer_contact_cta_stub.dart',
      'features/coach/presentation/widgets/trainer_day_detail_sheet.dart',
      'features/coach/presentation/widgets/trainer_inquiry_cta.dart',
      'features/coach/presentation/widgets/trainer_list_tile.dart',
      'features/coach/presentation/widgets/trainer_profile_hero.dart',
      'features/coach/presentation/widgets/trainer_specialty_chips.dart',
      'features/coach/presentation/widgets/trainers_map_bottom_sheet.dart',
      'features/coach/presentation/widgets/trainers_map_view.dart',
      'features/coach/trainer_coach_view.dart',
      'features/coach_hub/presentation/coach_hub_login_screen.dart',
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
      'features/coach_hub/presentation/sections/ajustes/tabs/apariencia_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_tab.dart',
      'features/coach_hub/presentation/sections/ajustes/tabs/seguridad_tab.dart',
      'features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart',
      'features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/biblioteca_filter_chips.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/exercise_detail_dialog.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/exercise_detail_panel.dart',
      'features/coach_hub/presentation/sections/biblioteca/widgets/exercise_grid_card.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_detail_pane.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_empty_pane.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_list_pane.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart',
      'features/coach_hub/presentation/sections/dashboard/widgets/dashboard_hero.dart',
      'features/coach_hub/presentation/sections/dashboard/widgets/dashboard_pending.dart',
      'features/coach_hub/presentation/sections/dashboard/widgets/dashboard_right_column.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/blocked_students_screen.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/keep_students_screen.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart',
      'features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart',
      'features/coach_hub/presentation/sections/invitaciones/widgets/solicitud_card.dart',
      'features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart',
      'features/coach_hub/presentation/widgets/athlete_picker_dialog.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/estado_cuenta_card.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/pagos_table.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/pagos_web_table.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart',
      'features/coach_hub/presentation/sections/perfil_publico/perfil_publico_screen.dart',
      'features/coach_hub/presentation/sections/perfil_publico/widgets/coach_discovery_preview_card.dart',
      'features/coach_hub/presentation/sections/perfil_publico/widgets/especialidad_precio_card.dart',
      'features/coach_hub/presentation/sections/perfil_publico/widgets/identidad_card.dart',
      'features/coach_hub/presentation/sections/planes/planes_screen.dart',
      'features/coach_hub/presentation/sections/planes/widgets/tarifa_card.dart',
      'features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart',
      'features/coach_hub/presentation/sections/rutinas/athlete_routines_screen.dart',
      'features/coach_hub/presentation/shell/coach_hub_sidebar.dart',
      'features/coach_hub/presentation/shell/coach_hub_top_bar.dart',
      'features/coach_hub/presentation/shell/mobile_banner.dart',
      'features/coach_hub/presentation/shell/proximamente_screen.dart',
      'features/feed/feed_screen.dart',
      'features/feed/presentation/create_post_screen.dart',
      'features/feed/presentation/follow_list_screen.dart',
      'features/feed/presentation/friend_requests_inbox_screen.dart',
      'features/feed/presentation/post_detail_screen.dart',
      'features/feed/presentation/public_profile_screen.dart',
      'features/feed/presentation/routine_tag_picker_sheet.dart',
      'features/feed/presentation/search_users_screen.dart',
      'features/feed/presentation/widgets/feed_empty_state.dart',
      'features/feed/presentation/widgets/friend_request_inbox_tile.dart',
      'features/feed/presentation/widgets/post_card.dart',
      'features/feed/presentation/widgets/post_privacy_selector.dart',
      'features/feed/presentation/widgets/post_reactions_row.dart',
      'features/feed/presentation/widgets/public_profile_follow_button.dart',
      'features/feed/presentation/widgets/public_profile_hero.dart',
      'features/feed/presentation/widgets/suggested_users_section.dart',
      'features/feed/presentation/widgets/unfriend_confirmation_sheet.dart',
      'features/feed/presentation/widgets/user_search_result_tile.dart',
      'features/feed/presentation/widgets/workout_snapshot_detail.dart',
      'features/gym_rankings/presentation/rankings_screen.dart',
      'features/home/widgets/daily_check_in_card.dart',
      'features/home/widgets/empezar_entrenamiento_card.dart',
      'features/home/widgets/esta_semana_card.dart',
      'features/home/widgets/home_cta_button.dart',
      'features/home/widgets/home_header.dart',
      'features/insights/presentation/exercise_progression_screen.dart',
      'features/insights/presentation/frequent_exercises_screen.dart',
      'features/insights/presentation/insights_screen.dart',
      'features/insights/presentation/measurements_screen.dart',
      'features/insights/presentation/monthly_report_screen.dart',
      'features/insights/presentation/muscle_distribution_screen.dart',
      'features/insights/presentation/volume_by_group_screen.dart',
      'features/insights/presentation/wellbeing_trend_screen.dart',
      'features/insights/presentation/widgets/body_silhouette_placeholder.dart',
      'features/insights/presentation/widgets/daily_heatmap_section.dart',
      'features/insights/presentation/widgets/day_strip_navigator.dart',
      'features/insights/presentation/widgets/monthly_report_chart.dart',
      'features/insights/presentation/widgets/monthly_report_summary_cards.dart',
      'features/insights/presentation/widgets/monthly_volume_by_group_card.dart',
      'features/insights/presentation/widgets/muscle_distribution_radar.dart',
      'features/insights/presentation/widgets/wellbeing_trend_chart.dart',
      'features/insights/presentation/widgets/workout_days_calendar.dart',
      'features/measurements/presentation/log_measurement_screen.dart',
      'features/measurements/presentation/widgets/measurement_history_list.dart',
      'features/measurements/presentation/widgets/measurement_progress_chart.dart',
      'features/notifications/presentation/notification_history_screen.dart',
      'features/onboarding/presentation/custom_exercise_onboarding_art.dart',
      'features/onboarding/presentation/onboarding_chrome.dart',
      'features/onboarding/presentation/onboarding_flow.dart',
      'features/onboarding/presentation/onboarding_module_card.dart',
      'features/onboarding/presentation/onboarding_previews.dart',
      'features/onboarding/presentation/onboarding_tour_view.dart',
      'features/onboarding/presentation/trainer_previews.dart',
      'features/onboarding/presentation/widgets/onboarding_nav_bar.dart',
      'features/onboarding/presentation/widgets/onboarding_preview_cards.dart',
      'features/onboarding/presentation/widgets/trainer_preview_kit.dart',
      'features/paywall/presentation/free_plan_limit_sheet.dart',
      'features/performance/presentation/log_performance_test_screen.dart',
      'features/performance/presentation/widgets/performance_progress_chart.dart',
      'features/profile/presentation/appearance_screen.dart',
      'features/profile/presentation/profile_edit_personal_screen.dart',
      'features/profile/presentation/profile_edit_trainer_screen.dart',
      'features/profile/presentation/profile_gym_screen.dart',
      'features/profile/presentation/profile_routines_screen.dart',
      'features/profile/presentation/widgets/eliminar_cuenta_sheet.dart',
      'features/profile/presentation/widgets/nearby_gyms_list.dart',
      'features/profile/presentation/widgets/pinned_current_gym.dart',
      'features/profile/presentation/widgets/profile_avatar_card.dart',
      'features/profile/presentation/widgets/profile_header.dart',
      'features/profile/presentation/widgets/profile_section_group.dart',
      'features/profile/presentation/widgets/profile_section_tile.dart',
      'features/profile/presentation/widgets/profile_trainer_section.dart',
      'features/profile/presentation/widgets/re_auth_bottom_sheet.dart',
      'features/profile/profile_screen.dart',
      'features/profile/trainer_profile_view.dart',
      'features/profile_setup/presentation/steps/step_1_username_avatar.dart',
      'features/profile_setup/presentation/steps/step_3_experience_gender.dart',
      'features/profile_setup/presentation/steps/step_4_weight_height.dart',
      'features/profile_setup/presentation/widgets/avatar_picker_button.dart',
      'features/profile_setup/presentation/widgets/experience_card.dart',
      'features/profile_setup/presentation/widgets/gender_chip.dart',
      'features/profile_setup/presentation/widgets/gym_card.dart',
      'features/profile_setup/presentation/widgets/gym_search_box.dart',
      'features/profile_setup/presentation/widgets/profile_setup_footer.dart',
      'features/profile_setup/presentation/widgets/profile_setup_header.dart',
      'features/reviews/presentation/widgets/review_bottom_sheet.dart',
      'features/reviews/presentation/widgets/review_cta.dart',
      'features/reviews/presentation/widgets/review_tile.dart',
      'features/reviews/presentation/widgets/trainer_reviews_section.dart',
      'features/watch/presentation/wear/wear_exercise_timer_screen.dart',
      'features/watch/presentation/wear/wear_routine_list.dart',
      'features/watch/presentation/wear/wear_today_page.dart',
      'features/watch/presentation/wear/wear_widgets.dart',
      'features/watch/presentation/wear/wear_workout_screen.dart',
      'features/workout/presentation/custom_exercise_editor_screen.dart',
      'features/workout/presentation/exercise_detail_screen.dart',
      'features/workout/presentation/onboarding/templates_onboarding_view.dart',
      'features/workout/presentation/post_workout_summary_screen.dart',
      'features/workout/presentation/routine_detail_screen.dart',
      'features/workout/presentation/routine_editor_screen.dart',
      'features/workout/presentation/session_detail_screen.dart',
      'features/workout/presentation/session_history_screen.dart',
      'features/workout/presentation/session_player_screen.dart',
      'features/workout/presentation/share_workout_composer_screen.dart',
      'features/workout/presentation/widgets/coach_chip.dart',
      'features/workout/presentation/widgets/coach_note.dart',
      'features/workout/presentation/widgets/day_tab_bar.dart',
      'features/workout/presentation/widgets/duration_set_row.dart',
      'features/workout/presentation/widgets/duration_text_field.dart',
      'features/workout/presentation/widgets/editor_footer_bar.dart',
      'features/workout/presentation/widgets/empty_day_state.dart',
      'features/workout/presentation/widgets/exercise_actions_sheet.dart',
      'features/workout/presentation/widgets/exercise_card.dart',
      'features/workout/presentation/widgets/exercise_feedback_note.dart',
      'features/workout/presentation/widgets/exercise_feedback_sheet.dart',
      'features/workout/presentation/widgets/exercise_progression_chart.dart',
      'features/workout/presentation/widgets/exercise_progression_section.dart',
      'features/workout/presentation/widgets/exercise_slot_row.dart',
      'features/workout/presentation/widgets/exercise_video_player.dart',
      'features/workout/presentation/widgets/feedback_load_error_note.dart',
      'features/workout/presentation/widgets/keyboard_accessory_bar.dart',
      'features/workout/presentation/widgets/most_frequent_exercises_list.dart',
      'features/workout/presentation/widgets/personal_records_list.dart',
      'features/workout/presentation/widgets/premium_chip.dart',
      'features/workout/presentation/widgets/prescription_chips.dart',
      'features/workout/presentation/widgets/quick_entry_panel.dart',
      'features/workout/presentation/widgets/resume_session_modal.dart',
      'features/workout/presentation/widgets/routine_action_buttons.dart',
      'features/workout/presentation/widgets/rutinas_section.dart',
      'features/workout/presentation/widgets/session_exercise_block.dart',
      'features/workout/presentation/widgets/session_highlights_section.dart',
      'features/workout/presentation/widgets/session_muscle_distribution_section.dart',
      'features/workout/presentation/widgets/set_cell_field.dart',
      'features/workout/presentation/widgets/set_entry_sheet.dart',
      'features/workout/presentation/widgets/set_type_chip.dart',
      'features/workout/presentation/widgets/stat_tile.dart',
      'features/workout/presentation/widgets/superset_block.dart',
      'features/workout/presentation/widgets/technique_instruction_item.dart',
      'features/workout/presentation/widgets/template_rating_sheet.dart',
      'features/workout/presentation/widgets/template_ratings_section.dart',
      'features/workout/presentation/widgets/templates_preferences_bar.dart',
      'features/workout/presentation/widgets/time_fit_sheet.dart',
      'features/workout/trainer_workout_view.dart',
      'main_wear_liveness_spike.dart',
      'main_wear_spike.dart',
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
            rawFontSizePattern.allMatches(entity.readAsStringSync()).length;
        totalDebt += matches;

        if (matches == 0) continue;
        seen.add(relativePath);
        if (!allowlist.contains(relativePath)) offenders.add(relativePath);
      }

      offenders.sort();
      staleEntries = allowlist.where((p) => !seen.contains(p)).toList()..sort();
    });

    test('ningún archivo fuera de la allowlist usa fontSize: <literal>', () {
      expect(
        offenders,
        isEmpty,
        reason: 'fontSize crudos fuera de la allowlist:\n'
            '${offenders.join('\n')}\n\n'
            'Para corregir: usá la escala de AppTextSize en vez del literal.\n'
            '  micro 10 · caption 12 · bodyDense 13 · body 14 · bodyLarge 16\n'
            '  title 18 · titleLarge 20 · heading 24 · display 28 · displayLarge 32\n\n'
            '  fontSize: 14  →  fontSize: AppTextSize.body\n\n'
            'Si tu valor NO está en la escala, no lo agregues a la allowlist: '
            'elegí el escalón más cercano, o seguí el proceso de excepción en '
            'docs/design-system.md → "Excepciones a la escala tipográfica".',
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
        lessThanOrEqualTo(rawFontSizeDebtCeiling),
        reason: 'Hay $totalDebt fontSize crudos en lib/ y el techo es '
            '$rawFontSizeDebtCeiling. Agregar uno a un archivo YA listado '
            'también rompe el ratchet: sin esta regla, 260 archivos podrían '
            'sumar deuda en silencio, que es como se llegó a 1879. Migrá a '
            'AppTextSize en vez de subir el techo.',
      );
    });

    test('la allowlist no tiene entradas muertas', () {
      expect(
        staleEntries,
        isEmpty,
        reason: 'Estos archivos ya no tienen fontSize crudo (o no existen) '
            'pero siguen en la allowlist:\n${staleEntries.join('\n')}\n\n'
            'Sacalos de la allowlist y bajá allowlistCeiling. El registro de '
            'deuda tiene que reflejar la deuda real.',
      );
    });
  });
}
