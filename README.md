# Offline Tasks

An offline-first task manager for Android, built with Flutter. You can use every feature
with no network. Changes are saved on the device right away and sync to Firebase
Firestore when a connection is available, without losing data or creating duplicate
records.

Built for **GDG Tech Wildcard: App Development, Task 1 (Offline-First Task Management App)**.

| | |
|---|---|
| Framework | Flutter (Dart 3), Material 3 |
| Local storage | Hive CE (on-device key-value database) |
| Remote database | Cloud Firestore (its own offline cache is **disabled**, so the sync logic is this app's) |
| Accounts | Firebase Auth: automatic guest account, plus email/password for multi-device |
| State management | `provider` + `ChangeNotifier` |

---

## Features

### Task management
- Create, edit and delete tasks. Swipe to delete, with **Undo**.
- Mark tasks complete or pending.
- Priorities (low / medium / high), deadlines (date + time), a **category** and any number of **tags**.
- **Search** across title, notes, tags and category.
- **Filter** by status, priority, category or tag. **Sort** by your own order, due date, priority or newest.

### Offline and persistence
- Every action works offline. Tasks are written to Hive *before* the UI updates.
- Tasks and unsynced changes survive closing, killing or restarting the app.
- An online/offline indicator in the app bar shows how many changes are waiting, plus a banner while offline.
- A **"Work offline" switch** (Settings) pauses all networking, so you can demo offline mode without airplane mode.

### Synchronization
- A persistent **outbox queue**: each unsynced change is listed with its attempts and last error (*Sync activity* screen).
- Automatic sync on startup, when the network returns, after each edit, when the app is resumed, every 30 s, and on demand (tap the status chip or pull to refresh).
- **Retries with exponential backoff** (2 s, 4 s, 8 s … up to 5 min) for failed uploads.
- **No duplicates**: ids are client-generated UUIDs and every upload carries an idempotency key (see below).
- **Conflict handling**: a field-level three-way merge with deterministic last-writer-wins for real collisions.
- **Recovery**: an interrupted sync resumes on the next launch, with nothing lost or doubled.
- Per-task sync badges: synced, waiting, failing/retrying, or conflict auto-resolved.

### Bonus features (all implemented)
- ✅ **Deadline notifications**: 30 minutes before and at the deadline. Scheduled locally, so they work offline.
- ✅ **Recurring tasks**: daily, weekly or monthly. Completing one creates the next occurrence.
- ✅ **Drag-and-drop reordering** (*My order* sort). The order syncs too.
- ✅ **Multi-device support**: create an account on one phone, sign in on another, and both stay in sync, with live updates while online.
- ✅ **Sync history / activity log**: every upload, download, retry, conflict and recovery is recorded.

---

## How it works

### Offline storage

```
UI ──► TaskRepository ──► Hive (records box)        ◄── source of truth
              │
              └── notifies ──► SyncEngine ──► Firestore
```

Each task is stored as **one record** in Hive:

```text
LocalRecord {
  task         // current local state (what the UI shows)
  base         // last version confirmed by the server: the common ancestor for merges
  baseRev      // server revision of `base`
  pending      // queued op { opId, queuedAt, attempts, nextAttemptAt, lastError } or null
}
```

The edit and its queue entry are in the **same record**, so they are written in a single
atomic `put`. The app can never crash *between* saving a change and queuing it for sync.
The outbox is simply every record whose `pending` is set, ordered by `queuedAt`.
Several edits to the same task while offline coalesce into one pending upload.

Deletions are **tombstones** (`deleted: true`), so a deletion made offline still reaches
the server and the other devices.

### Synchronization

One sync cycle has two steps:

1. **Push** every due queued change, oldest first, as a **conditional write** in a
   Firestore transaction:
   - If the server doc's `lastOpId` equals this op's id, the write already happened
     (e.g. the app died before it got the reply). It is marked done, **not written again**.
   - Else, if the server's `rev` still equals our `baseRev`, the server writes it with `rev + 1`.
   - Else someone else changed the task first, which is a **conflict** (next section).
   - On a network error the op stays queued with exponential backoff.
2. **Pull** every server doc with `serverUpdatedAt >= cursor` (incremental), then keep a
   live listener open while online so changes from other devices arrive instantly.
   A remote version is applied only if its `rev` is newer than what we have.

**Why there are no duplicates:**
- Task ids are UUIDv4 values generated on the device, and the Firestore document id *is* the task id.
  Re-uploading the same task overwrites the same document; it can never create a second one.
- The `opId` idempotency key makes retries after a lost response a no-op.
- Recurring follow-ups get a **deterministic UUIDv5** from (parent id + next due date).
  If two offline phones both complete the same recurring task, they create the *same*
  next task, not two.
- Firestore security rules require every write to increase `rev` by exactly 1, so the
  server itself rejects a stale overwrite.

### Conflict resolution

When the server has a newer revision than our base and we also have a local change,
the engine runs a **three-way merge** (`lib/sync/merge.dart`) between `base`, `local`
and `remote`, field by field:

| Situation | Result |
|---|---|
| Field changed on one side only | That side's value wins, so edits to *different* fields never overwrite each other (e.g. phone A renames a task and phone B changes its priority, and both changes survive) |
| Same field changed on both sides | **Last writer wins** on the edit timestamp, with device id as a tie-breaker, so every device resolves it identically |
| Tags changed on both sides | **Set merge**: additions and removals from both sides are kept |
| Deleted on one side, edited on the other | The delete wins, unless the edit happened *after* the delete; then the task is restored |

The merged result is pushed against the new revision. Each conflict is written to the
sync history, and the task shows a purple "merged" badge for a few minutes.

### Recovery

- Writes go to disk before the UI updates, so nothing the user sees can be lost.
- Pending ops are part of the stored record, so on restart the engine finds them,
  logs *"Resuming N unsynced change(s)…"* and continues.
- If the app is killed after the server applied a write but before the reply arrived,
  the `opId` check on the retry recognises it (logged as *"recovered after an
  interrupted upload"*).
- A user edit and a sync result can never overwrite each other: all record updates go
  through one async lock, and sync results are computed from the record *as it is at
  write time*.

---

## Project structure

```
lib/
  main.dart                     startup, dependency wiring, loading/error screen
  models/                       Task, LocalRecord + PendingOp, SyncLogEntry
  data/
    local_store.dart            Hive boxes: records, metadata, sync log
    task_repository.dart        all task reads/writes, atomic record updates
    remote_store.dart           remote interface (push / fetch / watch)
    firestore_remote_store.dart Firestore implementation (transactions)
  sync/
    sync_engine.dart            outbox processing, retries, pull, live updates
    merge.dart                  three-way field-level merge (pure function)
    connectivity_service.dart   network status + "work offline" switch
  services/                     auth (guest/email), deadline notifications
  ui/                           home list, editor, sync activity, settings
test/
  merge_test.dart               conflict rules
  sync_engine_test.dart         offline queue, retry/backoff, lost replies,
                                restart recovery, two-device conflicts,
                                tombstones, recurring dedupe, account switch
```

---

## Setup

Requirements: Flutter 3.38+ (built with 3.47) and an Android device or emulator (Android 7+).

```bash
git clone <this repo>
cd offline_tasks
flutter pub get
flutter run
```

The repo already contains a Firebase config (`lib/firebase_options.dart`,
`android/app/google-services.json`) for the project `offline-tasks-gdg26`.

**To use your own Firebase project instead:**
1. Create a project and enable **Cloud Firestore** and, under **Authentication**, the
   **Anonymous** and **Email/Password** sign-in providers.
2. Run `flutterfire configure` in this folder.
3. Deploy the security rules: `firebase deploy --only firestore:rules`.

Run the tests with `flutter test`. Build a release APK with `flutter build apk --release`;
it is written to `build/app/outputs/flutter-apk/app-release.apk`.

---

## Testing instructions (for judges)

Install the APK (from the GitHub Releases page) on an Android phone.

**1. Offline basics**
1. Open the app while online; the chip in the top-right says **Online**.
2. Turn on airplane mode, or go to ⋮ → *Settings* → **Work offline**. The chip turns to
   **Offline** and a banner appears.
3. Create, edit, complete and delete a few tasks. Add priorities, deadlines, tags and a
   category. Try search and the filter chips. Everything responds instantly.
4. Each changed task shows a cloud-upload icon, and the chip shows the pending count.

**2. Persistence and recovery**
1. While still offline, swipe the app away from recents (kill it) and reopen it. All tasks
   and the pending count are still there.
2. Go back online. The changes upload within seconds, the badges turn to ✓, and
   ⋮ → *Sync activity* shows *"Resuming N unsynced change(s)…"* followed by the uploads.

**3. Conflict handling (one device)**
1. Make sure a task is synced. Long-press it → **Simulate edit from another device**.
   This changes the server copy (title, priority, and a `#remote` tag).
2. Before the update arrives, or after turning **Work offline** on first, edit the same
   task locally, e.g. change its notes or due date.
3. Go online. Both edits are merged, and *Sync activity* shows a **Merged/Conflict** entry.
   If you change the *title* locally too, the newer title wins and the log names the
   conflicting field.

**4. Multi-device (two phones)**
1. Phone A: ⋮ → *Settings* → **Create** an account (email + password). The guest
   tasks stay attached to it.
2. Phone B: *Settings* → **Sign in to an existing account** with the same login.
3. Edits on one phone appear on the other within a second or two. Put both phones
   offline, edit the same task on each, then reconnect both, and watch them converge.

**5. Bonus features**
- Set a deadline a few minutes ahead to receive the 30-min / due notification.
- Set *Repeat* to daily, then complete the task; the next occurrence appears.
- In *Sort → My order*, drag tasks by the ≡ handle.
