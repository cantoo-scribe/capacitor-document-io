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

export interface DocumentIoPlugin {
  /**
   * Activate and remember the permission for a document the OS just handed the app.
   * Does not read the file.
   */
  prepareOpenedDocument(
    options: PrepareOpenedDocumentOptions
  ): Promise<PrepareOpenedDocumentResult>

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
