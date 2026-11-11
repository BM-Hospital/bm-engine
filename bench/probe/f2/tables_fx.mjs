// The cases of probe/f2/tables.mjs as fixtures, for `probe/paint/cmp.mjs --extra=probe/f2/tables_fx.mjs "^t-"`
// and `probe/paint/diff.mjs t-<name> --extra=probe/f2/tables_fx.mjs`.
import { cases } from "./tables.mjs";
export default Object.entries(cases).map(([n, node]) => ({ id: "t-" + n, feature: "f2-table", title: n, width: 360, height: 220, node }));
