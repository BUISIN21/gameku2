import { z } from 'zod';

const csv = z
  .string()
  .default('')
  .transform((s) =>
    s
      .split(',')
      .map((v) => v.trim())
      .filter((v) => v.length > 0),
  );

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  LIVEKIT_URL: z
    .string()
    .url()
    .refine((u) => /^wss?:\/\//.test(u), 'LIVEKIT_URL must start with ws:// or wss://'),
  LIVEKIT_API_KEY: z.string().min(1),
  LIVEKIT_API_SECRET: z.string().min(1),
  FIREBASE_PROJECT_ID: z.string().regex(/^[a-z0-9-]{4,40}$/, 'FIREBASE_PROJECT_ID looks invalid'),
  CORS_ORIGINS: csv,
  TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(3600).default(600),
  TRUST_PROXY: z.coerce.number().int().min(0).max(10).default(0),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error']).default('info'),
  // Set automatically by `firebase emulators:exec`; never set in production.
  FIREBASE_AUTH_EMULATOR_HOST: z.string().optional(),
  FIRESTORE_EMULATOR_HOST: z.string().optional(),
});

export type Env = z.infer<typeof EnvSchema>;

/** Parses and validates configuration. Throws with a readable message on error. */
export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const result = EnvSchema.safeParse(source);
  if (!result.success) {
    // Only variable names and messages are printed, never the values.
    const issues = result.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`);
    throw new Error(`Invalid configuration:\n${issues.join('\n')}`);
  }
  const env = result.data;
  const problems: string[] = [];
  if (env.NODE_ENV === 'production') {
    if (env.LIVEKIT_URL.startsWith('ws://')) problems.push('  - LIVEKIT_URL: production requires wss://');
    if (env.FIREBASE_AUTH_EMULATOR_HOST || env.FIRESTORE_EMULATOR_HOST) {
      problems.push('  - FIREBASE_*_EMULATOR_HOST: emulators must not be used in production');
    }
  }
  if (problems.length) throw new Error(`Invalid configuration:\n${problems.join('\n')}`);
  return env;
}
