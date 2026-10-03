# Safe Vault 1.3 feature status

These are implementation statuses, not a claim of device verification. Flutter/native tests have not been run in this workspace. See VALIDATION.md.

| Request | Status and location |
|---|---|
| Biometric freeze | Lifecycle/input handling rewritten; prompts no longer resume automatically across backgrounding, requests are guarded, a timeout and PIN cancellation path are provided. Physical-device verification required. |
| Larger, centred UI | Larger text/touch targets and navigation; width-filling summary cards; bounded content centred horizontally; empty states closer to vertical centre. Actual Flutter rendering still needs verification. |
| Receipt import | **Partial:** Tools → Receipt draft attaches screenshots/PDFs and parses pasted/text-file receipt text. Review merchant, price and renewal details before saving. No automatic image OCR. |
| Document scanner | **Partial:** Tools → Photo to PDF crops selected photos and combines up to eight pages. Camera capture is through your existing camera app. No automatic edges/perspective correction. |
| Multiple attachments | Item → Files & versions. Original attachment plus up to 30 extra files/versions, 10 MB per file. |
| Custom folders | Settings → Personalize → Folders. Assign from Organize or bulk actions; filter from Home. |
| OCR search | **Partial:** Organize → Searchable document text accepts pasted extracted text, included in global search. No built-in OCR engine. |
| Quick templates | Tools → Passport, College fee, Warranty, Monthly bill. |
| Custom dashboard | Personalize → Home cards enables/hides Summary and Spending and reverses their order; tabs can be hidden while keeping Home plus another tab. |
| Pinned items | Existing star/favourite control now places starred items first within each filtered list. |
| Subscription spending | Monthly and annual estimates by currency. No currency conversion or bank/payment-app connection. |
| Free-trial tracker | Organize → Trial & cancellation records trial end. Add an explicit alert in Extra reminders if required. |
| Price-change history | Changing an existing subscription amount records its old/new amount, currency and date; view in Organize. Last 100 changes retained. |
| Cancellation tracker | Cancellation deadline and confirmation status in Organize; receipts can be attached in Files. It does not cancel a service for you. |
| Warranty tracker | Purchase date, warranty end and service contact in document Organize. |
| Multiple reminders | Main reminder plus up to eight additional times in Organize. Main Reminder switch must be enabled. Nearest 60 events scheduled platform-wide. |
| Custom snooze | Reminder centre: minutes, next week, tomorrow 9 AM, custom delay/date/time. Moves the next relevant alert. |
| Quiet hours | Personalize: alerts within the window are postponed until its end. This can delay deadline alerts. Equal start/end means no postponement. |
| Renewal checklists | Organize creates up to 50 steps; check them off in item details. |
| Backup reminders | **Partial:** Home shows a backup nudge after seven days without a recorded backup. No independent background backup alert. |
| Duplicate detection | SHA-256 content comparison warns when adding through file manager or editor attachment picker. It does not automatically delete duplicates. |
| Storage manager | Tools or Settings → Storage lists files largest first, including versions and originals. Open to manage/delete copies. |
| Bulk actions | Long-press a list item; select more; move to folder, archive or trash from the selection menu. |
| Share to Safe Vault | **Deferred:** Android share intents and iOS share extension need native integration and device validation. Use in-app import. |
| Calendar export | Item → Export to calendar writes an unencrypted all-day .ics event containing title/due date. Import into your preferred calendar. |
| Document versions | Replacing an original or additional file retains its previous copy in Files → Show older versions. Deleting a file from the file manager permanently deletes that copy. |
| Expiring documents | Home → Show → Expiring includes active documents expired or due within 30 days. |
| English/Tamil | **Partial:** Preferences → Language translates navigation and common controls. Detailed guides, errors and some new tools remain English. |
| Accessibility | Personalize → Text size and high contrast; system text scaling retained. Existing reduced-motion setting retained. |
| Privacy-friendly widgets | Existing private native launch widgets retained. **Deferred:** live counts and new widget quick actions. |
| Optional cloud backup | **Partial:** encrypted backup can be saved through a cloud file provider exposed by your device's picker. Provider availability varies. No linked cloud account, automatic upload, sync or multi-device merging. |
| First-use guide | Home setup card → Guide covers PIN/recovery, reminders, files and backups; dismiss via Mark setup reviewed. |

## Limits

- Backups remain capped at 40 MB of total raw attachment data; the restore file limit is 80 MB. Extra files and old versions count toward this limit.
- File history upgrades the local database from schema 1 to schema 2. Do not reinstall older source against the upgraded database. Keep a 1.2 backup separately.
- Backups include records, metadata, original attachments, extra files and versions. Device PIN, recovery verifier, appearance settings and empty folder definitions are not transferred.
- Notification permission, device Focus/Do Not Disturb and battery restrictions can still affect alerts.
- Quiet hours change actual scheduled delivery time; the editor retains the originally chosen time. Reminder centre shows the effective quiet-hours time.
- No network OCR service receives your private documents. Native OCR, live camera scanning and cloud sync were deferred rather than adding unverified integrations.
