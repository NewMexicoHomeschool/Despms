// Resolve a static asset shipped in frontend/public against the build base.
// Dev: BASE_URL is "/", so asset("DezPMS-mark.svg") -> "/DezPMS-mark.svg".
// Prod: BASE_URL is "/assets/DezPMS/frontend/", so the same call resolves to
// "/assets/DezPMS/frontend/DezPMS-mark.svg" (where Frappe serves it).
export const asset = (path: string) =>
  import.meta.env.BASE_URL + path.replace(/^\//, "")
