import { registerPlugin } from '@capacitor/core'

import type { DocumentIoPlugin } from './definitions'

const DocumentIo = registerPlugin<DocumentIoPlugin>('DocumentIo', {
  web: () => import('./web').then(m => new m.DocumentIoWeb()),
})

export * from './definitions'
export { DocumentIo }
