// TODO: refresh token rotation needs review (per session log 2026-03-12)
export function refreshToken() {
  // FIXME: edge case when session expires mid-request
  return null;
}

// HACK: temp workaround for legacy user IDs — remove after migration done
export function legacyUserId(id: string) {
  return id.replace(/^legacy-/, "");
}
