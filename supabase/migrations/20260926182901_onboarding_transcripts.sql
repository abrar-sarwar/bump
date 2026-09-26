-- Onboarding transcripts: what a person said (or typed) while building their
-- card, saved by bump-api when they finish onboarding with cloud processing
-- allowed. Written only by the backend with the secret key; the app has no
-- database access. Audio is never stored.

create table public.onboarding_transcripts (
  id uuid primary key default gen_random_uuid(),
  -- Random per-install id from the phone, not a user account.
  install_id uuid not null,
  source text not null check (source in ('voice', 'typed')),
  transcript text not null check (char_length(transcript) between 1 and 2000),
  -- Typed-flow follow-ups: [{ "question": "...", "answer": "..." | null }]
  answers jsonb not null default '[]'::jsonb check (jsonb_typeof(answers) = 'array'),
  created_at timestamptz not null default now()
);

create index onboarding_transcripts_install_id_idx on public.onboarding_transcripts (install_id);

-- Server-only table: RLS on with no policies, and no grants to the public
-- roles, so the publishable key can neither read nor write it. The secret key
-- (service_role) bypasses RLS.
alter table public.onboarding_transcripts enable row level security;
revoke all on public.onboarding_transcripts from anon, authenticated;
