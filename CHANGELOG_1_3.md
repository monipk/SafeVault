# Safe Vault 1.3

- Removed the independently latched IgnorePointer gate; offstage content, stable keyed lock/privacy layers and focus exclusion now track privacy together.
- Native biometric authentication is single-request, non-persistent across backgrounding, time-bounded, and cancellable to PIN. Successful authentication reconciles the background timer. Cancel/failure never unlocks the vault.
- Larger controls and text, full-width cards, horizontally centred content and better empty-state placement.
- Added encrypted multiple attachments/version storage with a schema-1-to-2 migration. Backups include additional files and versions and can still read schema-1 backups.
- Added folders, pinned ordering, bulk operations, templates, spending estimates, tracked trial/cancellation/warranty dates, price history and checklists.
- Added extra reminders, custom snooze, quiet-hour postponement and calendar export.
- Added assisted receipt drafts, manual photo cropping/PDF assembly, storage management and duplicate warnings.
- Added dashboard/tab preferences, high contrast/text sizing, partial Tamil translations and a setup guide.
- Preserved the three-second dismissible delete Snackbar fix.
- Added lifecycle, migration, organizer/backup and reminder rule regression tests. Extended recovery test timeouts; installer runs tests serially with a five-minute timeout.

Read FEATURES_1_3.md for partial/deferred items. Read VALIDATION.md before installation.
