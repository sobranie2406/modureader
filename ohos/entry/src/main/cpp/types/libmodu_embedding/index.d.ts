export const isAvailable: () => boolean;
export const load: (modelPath: string) => Promise<void>;
export const embed: (ids: Uint8Array, dimensions: number) => Promise<number[]>;
export const close: () => Promise<void>;
export interface OcrTensorResult {
  data: ArrayBuffer;
  shape: number[];
}
export const ocrLoad: (path: string) => Promise<void>;
export const ocrRun: (name: string, data: Uint8Array, shape: number[]) => Promise<OcrTensorResult>;
export const ocrClose: () => Promise<void>;
