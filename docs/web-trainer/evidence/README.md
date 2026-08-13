# Evidencia Visual — Coach Hub Web

Capturas del shell (scaffold + sidebar + topbar) del Coach Hub web para comparar el estado visual antes y después de cada fase de rediseño.

## Estructura

```
docs/web-trainer/evidence/
└── fase-1/
    ├── before/          ← estado ANTES del rediseño
    │   ├── shell_dark_1440x900.png
    │   ├── shell_dark_420x900.png
    │   ├── shell_light_1440x900.png
    │   └── shell_light_420x900.png
    └── after/           ← estado DESPUÉS (generado al final de cada fase)
        └── ...
```

Matriz de capturas: dark 1440×900, dark 420×900, light 1440×900, light 420×900.

## Regenerar capturas BEFORE

Ejecutar **antes** de tocar cualquier widget del shell:

```bash
flutter test --update-goldens \
  --dart-define=EVIDENCE=true \
  --dart-define=EVIDENCE_DIR=before \
  test/evidence/
```

## Regenerar capturas AFTER

Ejecutar **después** de completar el rediseño de la fase:

```bash
flutter test --update-goldens \
  --dart-define=EVIDENCE=true \
  --dart-define=EVIDENCE_DIR=after \
  test/evidence/
```

## Fuentes

Los TTF (Barlow Regular/Medium/SemiBold/Bold y BarlowCondensed Regular/Bold) se almacenan en `test/fonts/` bajo licencia OFL (ver `test/fonts/OFL.txt`). Los goldens los cargan via `FontLoader`, sin red ni google_fonts en tiempo de test.

## Notas

- El harness usa `--dart-define=EVIDENCE=true` como guardián: `flutter test` normal salta el archivo por completo.
- Los goldens **no** se usan para CI de regresión automática; son evidencia manual de diseño.
- Cada fase genera su propio subdirectorio `before/` y `after/` para preservar el historial.
