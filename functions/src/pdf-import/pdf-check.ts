/**
 * pdf-check.ts — los topes del archivo que recibe `parsePlanPdf`, antes de
 * descontar cupo o llamar al LLM (contrato: header `%PDF-`, 5 MB, 20
 * paginas).
 *
 * Las paginas se cuentan con `pdf-lib` y no buscando `/Type /Page` en los
 * bytes: desde PDF 1.5 los objetos pueden viajar dentro de object streams
 * comprimidos, y ahi la busqueda textual da cero paginas. Un contador que
 * devuelve cero deja pasar un PDF de 300 paginas, que es exactamente el costo
 * que este tope existe para cortar.
 */
import { PDFDocument } from "pdf-lib";

export const PDF_MAX_BYTES = 5 * 1024 * 1024;
export const PDF_MAX_PAGES = 20;

/**
 * `encrypted`: un PDF con contraseña o cifrado. pdf-lib lo abre con
 * `ignoreEncryption` y cuenta paginas, pero el contenido no se puede leer, asi
 * que el LLM recibiria un archivo ilegible y el PF gastaria un import en nada.
 */
export type PdfRejectReason = "not_pdf" | "too_big" | "too_many_pages" | "encrypted";

export type PdfCheck =
  | { ok: true; bytes: Buffer; pages: number }
  | { ok: false; reason: PdfRejectReason };

const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;

/**
 * Decodifica y revisa el PDF. El tamaño se corta ANTES de decodificar (con el
 * largo del base64), para no reservar memoria por un archivo que se va a
 * rechazar igual.
 */
export async function checkPdf(pdfBase64: unknown): Promise<PdfCheck> {
  if (typeof pdfBase64 !== "string" || pdfBase64.length === 0) {
    return { ok: false, reason: "not_pdf" };
  }
  // 4 caracteres de base64 por cada 3 bytes, mas el relleno.
  if (pdfBase64.length > Math.ceil(PDF_MAX_BYTES / 3) * 4) {
    return { ok: false, reason: "too_big" };
  }
  // Buffer.from(…, "base64") ignora en silencio lo que no es base64: sin este
  // chequeo, basura con un "%PDF-" adentro pasaria como PDF.
  if (pdfBase64.length % 4 !== 0 || !BASE64.test(pdfBase64)) {
    return { ok: false, reason: "not_pdf" };
  }

  const bytes = Buffer.from(pdfBase64, "base64");
  if (bytes.length > PDF_MAX_BYTES) return { ok: false, reason: "too_big" };
  if (bytes.subarray(0, 5).toString("latin1") !== "%PDF-") {
    return { ok: false, reason: "not_pdf" };
  }

  let pages: number;
  let encrypted: boolean;
  try {
    const doc = await PDFDocument.load(bytes, {
      ignoreEncryption: true,
      updateMetadata: false,
      throwOnInvalidObject: false,
    });
    pages = doc.getPageCount();
    encrypted = doc.isEncrypted;
  } catch {
    return { ok: false, reason: "not_pdf" };
  }
  // `ignoreEncryption` hace que el load no tire con un PDF cifrado: hay que
  // preguntarlo explicito, y antes que las paginas (un cifrado de 30 paginas
  // es un cifrado, no un PDF largo).
  if (encrypted) return { ok: false, reason: "encrypted" };
  if (pages < 1) return { ok: false, reason: "not_pdf" };
  if (pages > PDF_MAX_PAGES) return { ok: false, reason: "too_many_pages" };

  return { ok: true, bytes, pages };
}
