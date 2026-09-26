// Writes to Supabase through its REST API (PostgREST). Uses the secret key,
// which bypasses RLS, so it must never leave this server. Errors carry no
// upstream body: it could echo user text.

import { storageError } from './errors.js';

/** Insert one onboarding transcript row. Resolves once Supabase has stored it. */
export async function insertTranscript(config, row) {
  const url = `${config.supabaseUrl.replace(/\/+$/, '')}/rest/v1/onboarding_transcripts`;
  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        apikey: config.supabaseSecretKey,
        'content-type': 'application/json',
        prefer: 'return=minimal',
      },
      body: JSON.stringify({
        install_id: row.installId,
        source: row.source,
        transcript: row.transcript,
        answers: row.answers,
      }),
      signal: AbortSignal.timeout(config.storageTimeoutMs),
    });
  } catch {
    throw storageError();
  }
  if (!res.ok) {
    config.log(`supabase insert failed: ${res.status}`);
    throw storageError();
  }
  await res.body?.cancel();
}
