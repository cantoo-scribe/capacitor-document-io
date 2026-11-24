# @cantoo/capacitor-document-io

Capacitor 7 plugin to read and write, in place, a document the system handed to the app (Files on iOS, “Open with” on Android).

The initial version is `0.1.0`. The host app remains responsible for declaring which file types it opens (`CFBundleDocumentTypes` / `UTExportedTypeDeclarations` in `Info.plist`, `VIEW`/`EDIT` `intent-filter` in `AndroidManifest`). This plugin does not register extensions.

There is no web implementation: in the browser the methods reject with “Not implemented on web.”

## Difference from `@capacitor/filesystem`

`@capacitor/filesystem` works with files in the app sandbox: `Directory.Data`, Cache, Documents, and paths the app itself controls. It creates, lists, moves, and deletes files in that area.

`@cantoo/capacitor-document-io` works with an external document opened by the system. Permission is not a plain-text path:

- on iOS it lives in the security-scoped `URL` object delivered on open;
- on Android it lives in the `content://` grant (`takePersistableUriPermission` when the intent allows it).

The plugin keeps that grant and writes over the same document. It does not list directories, create folders, or replace Filesystem. Use Filesystem for app storage and this plugin only for the file the user opened from outside.

## API

The name in `registerPlugin` is `DocumentIo`. Bytes are base64.

| Method | What it does |
| --- | --- |
| `prepareOpenedDocument({ url })` | Activates and remembers the permission. Does not read the file. Returns `{ uri }` for later calls. |
| `getInfo({ uri })` | Returns `{ name }` (display name with extension). On Android `content://` uses `OpenableColumns.DISPLAY_NAME`. |
| `read({ uri })` | Returns `{ data }` with the document bytes. |
| `write({ uri, data })` | Overwrites the same document without creating a sibling file. |
| `release({ uri })` | Releases the permission. On iOS this balances `startAccessingSecurityScopedResource()`. |

```ts
import { DocumentIo } from '@cantoo/capacitor-document-io'
import { App } from '@capacitor/app'

App.addListener('appUrlOpen', async ({ url }) => {
  const { uri } = await DocumentIo.prepareOpenedDocument({ url })
  const { data } = await DocumentIo.read({ uri })
  await DocumentIo.write({ uri, data })
  await DocumentIo.release({ uri })
})
```

On iOS the plugin also observes `capacitorOpenURL` and `ApplicationDelegateProxy`’s `lastURL`, to retain the original `URL` object before JavaScript calls `prepareOpenedDocument`. On Android, `handleOnNewIntent` tries to persist the `content://` grant.

Writes are in-place: on iOS without `NSFileCoordinator.WritingOptions.forReplacing` and without atomic write; on Android with `openOutputStream(uri, "wt")`. An atomic replace creates a new file next to the original, and the File Provider grant does not allow that — the document disappears from the folder.
