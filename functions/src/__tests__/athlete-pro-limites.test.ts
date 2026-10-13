import * as fs from "fs";
import * as path from "path";
import {
  ATHLETE_PRO_MAX_OWN_ROUTINES,
  ATHLETE_PRO_MAX_ROUTINE_DAYS,
  ATHLETE_PRO_MAX_ROUTINE_WEEKS,
} from "../subscriptions/athlete-plan-config";

// El mail del código nombra estos topes; la app los aplica desde Dart. Si se
// separan, el mail promete algo que la app no da.
const DART = path.resolve(__dirname, "../../../lib/features/paywall/domain/athlete_entitlement.dart");

function dartInt(nombre: string): number {
  const m = new RegExp(`const int ${nombre} = (\\d+);`).exec(fs.readFileSync(DART, "utf8"));
  if (!m) throw new Error(`No encontré ${nombre} en athlete_entitlement.dart`);
  return Number(m[1]);
}

describe("topes de TREINO Pro: TS espeja a Dart", () => {
  it.each([
    ["kMaxRoutineDays", ATHLETE_PRO_MAX_ROUTINE_DAYS],
    ["kMaxRoutineWeeks", ATHLETE_PRO_MAX_ROUTINE_WEEKS],
    ["kMaxOwnRoutines", ATHLETE_PRO_MAX_OWN_ROUTINES],
  ])("%s", (nombre, valorTs) => {
    expect(dartInt(nombre)).toBe(valorTs);
  });
});
