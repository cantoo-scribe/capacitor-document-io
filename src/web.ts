import { WebPlugin } from '@capacitor/core'

import type {
  DocumentInfoResult,
  DocumentIoPlugin,
  DocumentUriOptions,
  PrepareOpenedDocumentOptions,
  PrepareOpenedDocumentResult,
  ReadDocumentResult,
  WriteDocumentOptions,
} from './definitions'

export class DocumentIoWeb extends WebPlugin implements DocumentIoPlugin {
  prepareOpenedDocument(
    _options: PrepareOpenedDocumentOptions
  ): Promise<PrepareOpenedDocumentResult> {
    throw this.unimplemented('Not implemented on web.')
  }

  getInfo(_options: DocumentUriOptions): Promise<DocumentInfoResult> {
    throw this.unimplemented('Not implemented on web.')
  }

  read(_options: DocumentUriOptions): Promise<ReadDocumentResult> {
    throw this.unimplemented('Not implemented on web.')
  }

  write(_options: WriteDocumentOptions): Promise<void> {
    throw this.unimplemented('Not implemented on web.')
  }

  release(_options: DocumentUriOptions): Promise<void> {
    throw this.unimplemented('Not implemented on web.')
  }
}
