export const isAvailable: () => boolean;
export const load: (modelPath: string) => Promise<void>;
export const embed: (ids: BigInt64Array, dimensions: number) => Promise<number[]>;
export const close: () => Promise<void>;
