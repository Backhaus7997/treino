/// Dedupe de etiquetas para ejes X basados en índice de punto (#383, #554).
///
/// fl_chart samplea los bottom titles en Xs FRACCIONARIAS cuando `SideTitles`
/// no fija `interval`: elige tantos samples como entran en el ancho del chart,
/// y `value.round()` mapea samples vecinos al mismo índice de punto → etiquetas
/// de fecha duplicadas y otras salteadas. Ya pasó dos veces — #383 en el chart
/// de progresión por ejercicio (PR #463) y #554 en el de Medidas — así que el
/// criterio vive acá, compartido, y no se resuelve una tercera vez.
///
/// ## Contrato
///
/// Un chart con eje X índice-de-punto debe hacer DOS cosas:
/// 1. Fijar `interval: 1` en sus `SideTitles` — así fl_chart samplea en
///    índices enteros y las etiquetas efectivamente aparecen.
/// 2. Renderizar sólo cuando el sample cae exactamente en un índice —
///    [exactPointIndex] implementa esta mitad: devuelve el índice entero, o
///    `null` si `value` quedó a más de [tolerance] de uno (residuo de
///    sampling fraccionario → el caller devuelve `SizedBox.shrink()`).
library;

/// Índice de punto entero para un `value` sampleado por fl_chart, o `null`
/// si el sample es fraccionario (no corresponde a ningún punto).
int? exactPointIndex(double value, {double tolerance = 0.01}) {
  final idx = value.round();
  if ((value - idx).abs() > tolerance) return null;
  return idx;
}
