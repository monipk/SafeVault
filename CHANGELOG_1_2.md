# 1.2.0 — UI and access recovery

- Rebuilt home layout with short navigation, one Add action, filters, sorting and date filtering.
- Grouped Settings into individual pages; added a separate Guide.
- Added optional glass cards, eight accent palettes and reduced-motion-aware custom transitions.
- Simplified reminder centre and editor labels; added unsaved-change protection.
- Added biometric-first unlock and an inline Forgot PIN form.
- Added hashed single-use recovery codes with persistent throttling; no vault-data deletion for PIN reset.
- Removed user-facing test/diagnostic controls and bulk erase.
- Kept file_picker 13 API fix and fixed mixed Windows path separators in resource copying.
- Added security recovery and compact UI regression tests (supplied, not run in this workspace).

See UI_UPDATE.md and VALIDATION.md before installation.

## Snackbar hotfix

The delete Undo message now explicitly uses persist: false, a three-second duration and a close icon. Old queued messages are cleared before showing the new deletion message. Source syntax checked; Flutter runtime validation remains pending.
