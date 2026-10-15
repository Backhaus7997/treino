import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

class ExcelParseException implements Exception {
  ExcelParseException(this.message);
  final String message;
  @override
  String toString() => 'ExcelParseException: $message';
}

/// Ruta del mapa de relaciones del workbook adentro del `.xlsx`.
const _relsWorkbook = 'xl/_rels/workbook.xml.rels';

/// Pasa los `Target` ABSOLUTOS de las relaciones a relativos.
///
/// Un `.xlsx` puede declarar sus partes de dos formas, y las dos son OOXML
/// válido:
///
///     Target="worksheets/sheet1.xml"      relativo a `xl/`
///     Target="/xl/worksheets/sheet1.xml"  absoluto desde la raíz del paquete
///
/// El paquete `excel` sólo entiende la primera: hace
/// `archive.findFile('xl/$target')`, que con la segunda arma
/// `xl//xl/worksheets/sheet1.xml`, no encuentra nada, y revienta en un `!`
/// (`parse.dart:540`, `Null check operator used on a null value`).
///
/// El PF exportó su plan con una herramienta que escribe la forma absoluta
/// —openpyxl y varias más lo hacen— y la app le contestó «El archivo no es un
/// Excel válido» sobre un archivo perfectamente válido, armado con NUESTRO
/// template y con las seis hojas correctas.
///
/// Se reescribe sólo el mapa de relaciones y sólo si hace falta: si no hay
/// ningún target absoluto se devuelven los bytes originales sin tocar, así el
/// camino normal no paga ni una recompresión.
Uint8List _targetsRelativos(Uint8List bytes) {
  final Archive archivo;
  try {
    archivo = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    // No es ni un ZIP. Que siga y falle en `decodeBytes`, que ahí el mensaje
    // «no es un Excel válido» SÍ es cierto.
    return bytes;
  }

  final rels = archivo.findFile(_relsWorkbook);
  if (rels == null) return bytes;

  final String xml;
  try {
    xml = utf8.decode(rels.content as List<int>);
  } catch (_) {
    return bytes;
  }
  if (!xml.contains('Target="/')) return bytes;

  // `/xl/worksheets/sheet1.xml` → `worksheets/sheet1.xml`. Se saca la barra y
  // también el `xl/`, porque el paquete lo antepone él mismo.
  final corregido = xml.replaceAllMapped(
    RegExp(r'Target="/(?:xl/)?([^"]*)"'),
    (m) => 'Target="${m.group(1)}"',
  );

  final salida = Archive();
  for (final f in archivo.files) {
    if (f.name == _relsWorkbook) {
      salida.addFile(ArchiveFile.string(_relsWorkbook, corregido));
    } else {
      salida.addFile(f);
    }
  }
  final zip = ZipEncoder().encode(salida);
  return zip == null ? bytes : Uint8List.fromList(zip);
}

/// Decodifica el `.xlsx` tolerando los `Target` absolutos de OOXML. Es el
/// único camino de lectura del import (`parsePeriodizedExcel`).
Excel decodeWorkbookBytes(Uint8List bytes) {
  try {
    return Excel.decodeBytes(_targetsRelativos(bytes));
  } catch (e) {
    // El mensaje NOMBRA el motivo. Antes era un `catch (_)` con un texto fijo:
    // el PF veía «no es un Excel válido» sobre un archivo válido y no había
    // forma de saber por qué, ni para él ni para nosotros.
    throw ExcelParseException('No pudimos leer el Excel. Detalle: $e');
  }
}
