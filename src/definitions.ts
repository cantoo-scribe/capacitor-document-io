export interface PrepareOpenedDocumentOptions {
  /**
   * URL the system used to open the app (`file://` on iOS, `content://` or `file://` on Android).
   */
  url: string
}

export interface PrepareOpenedDocumentResult {
  /**
   * URI to pass to `read`, `write`, and `release`.
   * Use this value, not the original string, when the native side canonicalizes it.
   */
  uri: string
}

export interface DocumentUriOptions {
  uri: string
}

export interface ReadDocumentResult {
  /** File bytes, base64-encoded. */
  data: string
}

export interface WriteDocumentOptions {
  uri: string
  /** File bytes, base64-encoded. */
  data: string
}

export interface DocumentInfoResult {
  /**
   * Display name of the document (e.g. `note.txt`).
   * On Android `content://` URIs this comes from `OpenableColumns.DISPLAY_NAME`.
   * On iOS / `file://` it is the URL's last path component.
   */
  name: string
}

export interface DocumentIoPlugin {
  /**
   * Activate and remember the permission for a document the OS just handed the app.
   * Does not read the file.
   */
  prepareOpenedDocument(
    options: PrepareOpenedDocumentOptions
  ): Promise<PrepareOpenedDocumentResult>

  /**
   * Resolve the document's display name (including extension when the provider supplies it).
   * Useful for `content://` URIs whose path has no file extension.
   */
  getInfo(options: DocumentUriOptions): Promise<DocumentInfoResult>

  /** Read the prepared document. */
  read(options: DocumentUriOptions): Promise<ReadDocumentResult>

  /**
   * Overwrite the same document in place.
   * Does not create a sibling file or replace the document identity.
   */
  write(options: WriteDocumentOptions): Promise<void>

  /**
   * Drop the retained permission.
   * On iOS this balances `startAccessingSecurityScopedResource()`.
   */
  release(options: DocumentUriOptions): Promise<void>
}
