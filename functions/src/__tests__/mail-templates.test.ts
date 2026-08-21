/**
 * Unit tests for the transactional email templates and formatters.
 *
 * Pure — no emulator, no network. Run with plain `npx jest mail-templates`.
 *
 * Covers:
 *   - HTML escaping of user-controlled display names (the injection surface)
 *   - both MIME parts present and non-empty for every MailKind
 *   - ART rendering of dates, times and amounts
 */

import { renderMail } from "../mail/templates";
import { MailKind } from "../mail/types";
import {
  artDateKey,
  formatArs,
  formatDateAR,
  formatShortDateAR,
  formatTimeAR,
  toDate,
} from "../mail/format";

const ALL_KINDS: MailKind[] = [
  "appointment-confirmed",
  "appointment-series-created",
  "appointment-cancelled",
  "appointment-series-cancelled",
  "link-requested",
  "link-accepted",
  "payment-overdue",
];

// ---------------------------------------------------------------------------
// Escaping — display names are user-controlled free text
// ---------------------------------------------------------------------------
describe("renderMail: escapes user-controlled values", () => {
  const NASTY = "<script>alert('x')</script>";

  it("never emits a raw script tag from a display name", () => {
    const out = renderMail("link-requested", { athleteName: NASTY });

    expect(out.html).not.toContain("<script>");
    expect(out.html).toContain("&lt;script&gt;");
  });

  it("escapes quotes so a name cannot break out of an attribute", () => {
    const out = renderMail("link-accepted", {
      trainerName: '" onmouseover="evil()',
    });

    expect(out.html).not.toContain('onmouseover="evil()"');
    expect(out.html).toContain("&quot;");
  });

  it("escapes ampersands without double-escaping the entities it creates", () => {
    const out = renderMail("link-accepted", { trainerName: "Ruiz & Co" });

    expect(out.html).toContain("Ruiz &amp; Co");
    expect(out.html).not.toContain("&amp;amp;");
  });
});

// ---------------------------------------------------------------------------
// Every kind renders both MIME parts
// ---------------------------------------------------------------------------
describe("renderMail: every MailKind produces a complete message", () => {
  it.each(ALL_KINDS)("%s has subject, html and text", (kind) => {
    const out = renderMail(kind, {
      trainerName: "Jose",
      athleteName: "Marta",
      otherName: "Jose",
      dateLabel: "martes 26 de agosto",
      timeLabel: "19:00",
      amountLabel: "$ 25.000",
      dueLabel: "26/08/2026",
    });

    expect(out.subject.length).toBeGreaterThan(0);
    expect(out.text.length).toBeGreaterThan(0);
    expect(out.html).toContain("<!doctype html>");
    // A missing text/plain alternative is itself a spam signal.
    expect(out.text).not.toContain("<");
  });

  it("degrades to empty strings instead of throwing on missing params", () => {
    expect(() => renderMail("appointment-confirmed", {})).not.toThrow();
  });

  it("carries the brand accent so the mail is recognisably TREINO", () => {
    const out = renderMail("appointment-confirmed", { trainerName: "Jose" });
    expect(out.html).toContain("#2CE5A2");
  });
});

// ---------------------------------------------------------------------------
// Formatters — ART, not UTC
// ---------------------------------------------------------------------------
describe("format: renders in America/Argentina/Buenos_Aires", () => {
  // 2026-08-26T22:00:00Z is 19:00 on the 26th in ART (UTC-3).
  const EVENING = new Date("2026-08-26T22:00:00Z");

  it("formats the time in ART, not UTC", () => {
    expect(formatTimeAR(EVENING)).toBe("19:00");
  });

  it("formats the date in es-AR", () => {
    const out = formatDateAR(EVENING);
    expect(out).toContain("26");
    expect(out.toLowerCase()).toContain("agosto");
  });

  it("keeps the ART calendar day when UTC has already rolled over", () => {
    // 02:00Z on the 27th is still 23:00 on the 26th in Buenos Aires.
    const afterMidnightUtc = new Date("2026-08-27T02:00:00Z");
    expect(artDateKey(afterMidnightUtc)).toBe("2026-08-26");
    expect(formatShortDateAR(afterMidnightUtc)).toBe("26/08/2026");
  });

  it("returns an empty string for an unusable date rather than throwing", () => {
    expect(formatTimeAR(undefined)).toBe("");
    expect(formatDateAR(undefined)).toBe("");
    expect(toDate(undefined)).toBeNull();
  });

  it("accepts the plain _seconds shape a Timestamp takes after JSON", () => {
    const seconds = Math.floor(EVENING.getTime() / 1000);
    expect(formatTimeAR({ _seconds: seconds })).toBe("19:00");
  });
});

describe("formatArs", () => {
  it("renders whole pesos without centavos", () => {
    const out = formatArs(25000);
    expect(out).toContain("25.000");
    expect(out).not.toContain(",00");
  });

  it("returns an empty string for a missing amount", () => {
    expect(formatArs(undefined)).toBe("");
    expect(formatArs(Number.NaN)).toBe("");
  });
});
