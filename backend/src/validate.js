// Pure validation and grounding helpers. No I/O here, so everything is
// easy to unit test.
//
// Two jobs:
//   1. Check what the app sends us (request shapes and limits → 400).
//   2. Check what the model sends back: every fact must be grounded in the
//      user's own words, questions must be real questions, ids must exist.
//      Bad items are dropped; if something required is left empty → 502.

import { badRequest, upstreamInvalid } from './errors.js';

export const KINDS = ['interest', 'experience', 'goal'];

// Limits from CONTRACT.md, in one place.
export const LIMITS = {
  transcript: 2000,
  catalogLabels: 150,
  catalogLabel: 40,
  known: 30,
  asked: 3,
  askedQuestion: 300, // not in the contract; generous cap so a body can't be abused
  answer: 500,
  label: 60,
  source: 200,
  bio: 200,
  bioSources: 5,
  draftFacts: 12,
  followupFacts: 6,
  draftQuestion: 160,
  followupQuestion: 160,
  candidates: 8,
  candidateId: 80,
  candidateLabel: 60,
  points: 4,
  prompt: 180,
};

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

/** Length in Unicode code points (so emoji count as one, like the user sees). */
export function charLength(s) {
  return Array.from(s).length;
}

/** Clip to at most `max` code points, then trim the end. */
export function clip(s, max) {
  const chars = Array.from(s);
  return chars.length <= max ? s : chars.slice(0, max).join('').trimEnd();
}

/** Trim and collapse internal whitespace (newlines, double spaces). */
export function tidy(s) {
  return s.replace(/\s+/g, ' ').trim();
}

/**
 * House style: no em/en dashes in anything the app shows. "piano—what" and
 * "piano — what" both become "piano, what". Only applied to text we generate
 * (bio, labels, questions), never to the user's own quoted words.
 */
export function noDashes(s) {
  return s.replace(/\s*[\u2014\u2013]\s*/g, ', ').replace(/,\s*,/g, ',').trim();
}

/**
 * Fold text for comparison: lowercase, strip diacritics, straighten curly
 * quotes, turn everything that is not a letter/number into a space, collapse
 * whitespace. "Café, I’m into JAZZ!" → "cafe i m into jazz".
 */
export function fold(s) {
  return String(s)
    .normalize('NFKD')
    .replace(/\p{M}/gu, '') // combining marks (the diacritics NFKD split off)
    .toLowerCase()
    .replace(/[‘’‚‛′]/g, "'")
    .replace(/[“”„‟″]/g, '"')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * A source is grounded iff its folded form is ≥ 2 chars and occurs in the
 * folded user text on word boundaries, so "ja" is NOT grounded in "jazz".
 */
// Evidence rules, mirrored in the app (Grounding in BumpAPI.swift).
const NEGATIONS = ["don't", 'dont', 'do not', 'does not', "doesn't", 'doesnt', 'not', 'never', 'no longer',
  'hate', 'hated', 'dislike', "can't stand", 'cant stand', 'not a fan', 'not into', 'used to',
  "isn't", 'isnt', "aren't", 'arent', "wasn't", 'wasnt'];
const OTHER_PEOPLE = ['my friend', 'my friends', 'my brother', 'my sister', 'my mom', 'my mum', 'my dad',
  'my partner', 'my girlfriend', 'my boyfriend', 'my wife', 'my husband', 'my roommate', 'my kid',
  'my son', 'my daughter', 'my cousin', 'my coworker', 'my colleague', 'he likes', 'she likes',
  'he loves', 'she loves', 'they like', 'they love', 'he is into', 'she is into'];

/** Clauses split on sentence punctuation, commas and "but". */
export function clauses(text) {
  return String(text).replace(/\s+but\s+/gi, '.').split(/[.;!?,\n]/).map((c) => c.trim()).filter(Boolean);
}

/** Clauses that state something positive about the speaker themselves. */
export function affirmativeClauses(text) {
  return clauses(text).filter((c) => {
    const raw = ` ${c.toLowerCase().replace(/\u2019/g, "'")} `;
    const f = ` ${fold(c)} `;
    const negated = NEGATIONS.some((n) => raw.includes(` ${n} `) || f.includes(` ${fold(n)} `));
    const other = OTHER_PEOPLE.some((p) => f.includes(` ${fold(p)} `));
    return !negated && !other;
  });
}

/** The excerpt sits in a positive clause about the speaker. */
export function isAffirmative(excerpt, userText) {
  return affirmativeClauses(userText).some((c) => isGrounded(excerpt, c) || isGrounded(c, excerpt));
}

/** Every meaningful word of the label is in ONE positive clause. */
export function labelSupported(label, userText) {
  const filler = new Set(['a', 'an', 'the', 'of', 'and', 'to', 'in', 'on', 'at']);
  const words = fold(label).split(' ').filter((w) => w && !filler.has(w));
  if (!words.length) return false;
  return affirmativeClauses(userText).some((c) => {
    const have = new Set(fold(c).split(' '));
    return words.every((w) => have.has(w) || have.has(`${w}s`) || (w.endsWith('s') && have.has(w.slice(0, -1))));
  });
}

export function isGrounded(source, userText) {
  const f = fold(source);
  return f.length >= 2 && ` ${fold(userText)} `.includes(` ${f} `);
}

/** No compatibility scores or percentages: we have no data to back them. */
export function inventsScores(s) {
  const lower = String(s).toLowerCase();
  return lower.includes('%') || lower.includes('percent') || lower.includes('compatib');
}

// ---------------------------------------------------------------------------
// Request validation (→ 400 bad_request)
// ---------------------------------------------------------------------------

function requireObject(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw badRequest('Body must be a JSON object.');
  }
}

function stringField(value, name, { min = 0, max }) {
  if (typeof value !== 'string') throw badRequest(`"${name}" must be a string.`);
  const len = charLength(value);
  if (len < min || len > max) {
    throw badRequest(`"${name}" must be ${min}..${max} characters.`);
  }
  return value;
}

function arrayField(value, name, max) {
  if (!Array.isArray(value)) throw badRequest(`"${name}" must be an array.`);
  if (value.length > max) throw badRequest(`"${name}" must have at most ${max} items.`);
  return value;
}

/** catalogLabels is optional; empty strings are ignored. */
function catalogLabelsField(value) {
  if (value === undefined) return [];
  return arrayField(value, 'catalogLabels', LIMITS.catalogLabels)
    .map((label, i) => stringField(label, `catalogLabels[${i}]`, { max: LIMITS.catalogLabel }).trim())
    .filter(Boolean);
}

export function parseDraftRequest(body) {
  requireObject(body);
  const transcript = stringField(body.transcript, 'transcript', { min: 1, max: LIMITS.transcript });
  if (!transcript.trim()) throw badRequest('"transcript" must not be blank.');
  return { transcript, catalogLabels: catalogLabelsField(body.catalogLabels) };
}

export function parseFollowupRequest(body) {
  requireObject(body);
  const known = arrayField(body.known ?? [], 'known', LIMITS.known).map((item, i) => {
    if (item === null || typeof item !== 'object' || !KINDS.includes(item.kind)) {
      throw badRequest(`"known[${i}].kind" must be one of ${KINDS.join(', ')}.`);
    }
    const label = stringField(item.label, `known[${i}].label`, { max: LIMITS.label });
    return { kind: item.kind, label };
  });
  const asked = arrayField(body.asked ?? [], 'asked', LIMITS.asked).map((q, i) =>
    stringField(q, `asked[${i}]`, { max: LIMITS.askedQuestion }),
  );
  const answer = stringField(body.answer ?? '', 'answer', { max: LIMITS.answer });
  // Optional app-chosen topic for the next question: [{ id, purpose }].
  let topic = null;
  if (Array.isArray(body.topic) && body.topic[0] && typeof body.topic[0] === 'object') {
    topic = {
      id: stringField(body.topic[0].id, 'topic.id', { min: 1, max: 60 }),
      purpose: stringField(body.topic[0].purpose, 'topic.purpose', { min: 1, max: 160 }),
    };
  }
  return { known, asked, answer, topic, catalogLabels: catalogLabelsField(body.catalogLabels) };
}

export function parseTalkingPointsRequest(body) {
  requireObject(body);
  const candidates = arrayField(body.candidates, 'candidates', LIMITS.candidates).map((c, i) => {
    if (c === null || typeof c !== 'object') throw badRequest(`"candidates[${i}]" must be an object.`);
    if (c.kind !== 'shared' && c.kind !== 'complementary') {
      throw badRequest(`"candidates[${i}].kind" must be "shared" or "complementary".`);
    }
    return {
      id: stringField(c.id, `candidates[${i}].id`, { min: 1, max: LIMITS.candidateId }),
      kind: c.kind,
      mine: stringField(c.mine, `candidates[${i}].mine`, { min: 1, max: LIMITS.candidateLabel }),
      theirs: stringField(c.theirs, `candidates[${i}].theirs`, { min: 1, max: LIMITS.candidateLabel }),
    };
  });
  return { candidates };
}

// ---------------------------------------------------------------------------
// Model output validation
// ---------------------------------------------------------------------------

const factKey = (kind, label) => `${kind}\u0000${fold(label)}`;

/**
 * Keep only well-formed, grounded, non-duplicate facts, up to `max`.
 * `exclude` is a list of {kind,label} the user already has (followup).
 */
export function groundFacts(rawFacts, userText, { max, exclude = [], broad = [] }) {
  // Broad catalogue categories ("Music") may be worded differently from the
  // person's words; anything specific must appear in them.
  const broadLabels = new Set(broad.map(fold));
  if (!Array.isArray(rawFacts)) throw upstreamInvalid();
  const seen = new Set(exclude.map((f) => factKey(f.kind, f.label)));
  const facts = [];
  for (const raw of rawFacts) {
    if (facts.length >= max) break;
    if (raw === null || typeof raw !== 'object') continue;
    if (!KINDS.includes(raw.kind)) continue;
    if (typeof raw.label !== 'string' || typeof raw.source !== 'string') continue;

    const label = clip(noDashes(tidy(raw.label)), LIMITS.label);
    const source = clip(raw.source.trim(), LIMITS.source);
    if (!label || !fold(label)) continue;
    if (!isGrounded(source, userText)) continue;
    // Valid JSON is not evidence: the quote must be a positive statement
    // about the speaker, and an interest's label must come from their words.
    if (!isAffirmative(source, userText)) continue;
    if (raw.kind === 'interest' && !labelSupported(label, userText) && !broadLabels.has(fold(label))) continue;

    const key = factKey(raw.kind, label);
    if (seen.has(key)) continue;
    seen.add(key);
    facts.push({ kind: raw.kind, label, source });
  }
  return facts;
}

/**
 * A usable question: a string that (after trimming) ends in "?", fits in
 * `max`, has some real words, and does not repeat anything in `asked`.
 * Returns the tidied question or null. Over-long questions are rejected
 * rather than clipped, because clipping would cut off the "?".
 */
export function cleanQuestion(q, { max, asked = [] }) {
  if (typeof q !== 'string') return null;
  const text = noDashes(tidy(q));
  if (!text.endsWith('?') || charLength(text) > max) return null;
  const folded = fold(text);
  if (folded.length < 2) return null;
  if (asked.some((a) => fold(a) === folded)) return null;
  if (inventsScores(text)) return null;
  return text;
}

function requireOutputObject(raw) {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) throw upstreamInvalid();
}

/** Draft: {bio_text, bio_sources, facts, question} → contract shape. */
export function checkDraftOutput(raw, { transcript }) {
  requireOutputObject(raw);
  const facts = groundFacts(raw.facts, transcript, { max: LIMITS.draftFacts });

  let bio = null;
  if (typeof raw.bio_text === 'string' && Array.isArray(raw.bio_sources)) {
    const text = clip(noDashes(tidy(raw.bio_text)), LIMITS.bio);
    const sources = raw.bio_sources
      .filter((s) => typeof s === 'string')
      .map((s) => clip(s.trim(), LIMITS.source))
      .filter((s) => isGrounded(s, transcript))
      .slice(0, LIMITS.bioSources);
    if (text && sources.length > 0) bio = { text, sources };
  }

  const question = cleanQuestion(raw.question, { max: LIMITS.draftQuestion });
  return { bio, facts, question };
}

/** Followup: facts grounded in `answer` only; question never repeats `asked`. */
export function checkFollowupOutput(raw, { answer, asked, known }) {
  requireOutputObject(raw);
  const facts = answer.trim()
    ? groundFacts(raw.facts, answer, { max: LIMITS.followupFacts, exclude: known })
    : [];
  // The server, not the model, decides when the interview is over.
  const question =
    asked.length >= LIMITS.asked
      ? null
      : cleanQuestion(raw.question, { max: LIMITS.followupQuestion, asked });
  return { facts, question };
}

/** Talking points: known, unique ids only; ≤ 4; opener is required. */
export function checkTalkingPointsOutput(raw, { candidates }) {
  requireOutputObject(raw);
  const ids = new Set(candidates.map((c) => c.id));
  const used = new Set();
  const points = [];
  if (Array.isArray(raw.points)) {
    for (const p of raw.points) {
      if (points.length >= LIMITS.points) break;
      if (p === null || typeof p !== 'object') continue;
      if (typeof p.candidateId !== 'string' || !ids.has(p.candidateId) || used.has(p.candidateId)) continue;
      const prompt = cleanQuestion(p.prompt, { max: LIMITS.prompt });
      if (!prompt) continue;
      used.add(p.candidateId);
      points.push({ candidateId: p.candidateId, prompt });
    }
  } else {
    throw upstreamInvalid();
  }
  const opener = cleanQuestion(raw.opener, { max: LIMITS.prompt });
  if (!opener) throw upstreamInvalid();
  return { points, opener };
}

// ---------------------------------------------------------------------------
// Interest tagging
// ---------------------------------------------------------------------------

export function parseTagRequest(body) {
  requireObject(body);
  const interests = arrayField(body.interests, 'interests', 30).map((x, i) =>
    stringField(x, `interests[${i}]`, { min: 1, max: 80 }));
  const vocabulary = arrayField(body.vocabulary, 'vocabulary', 200).map((v, i) => {
    if (v === null || typeof v !== 'object') throw badRequest(`"vocabulary[${i}]" must be an object.`);
    return {
      id: stringField(v.id, `vocabulary[${i}].id`, { min: 1, max: 40 }),
      label: stringField(v.label, `vocabulary[${i}].label`, { min: 1, max: 60 }),
    };
  });
  return { interests, vocabulary };
}

/** Keep only asked-about interests and ids that exist in the vocabulary. */
export function checkTagOutput(raw, { interests, vocabulary }) {
  requireOutputObject(raw);
  if (!Array.isArray(raw.tags)) throw upstreamInvalid();
  const allowed = new Set(vocabulary.map((v) => v.id));
  const asked = new Map(interests.map((x) => [fold(x), x]));
  const tags = {};
  for (const t of raw.tags) {
    const label = asked.get(fold(String(t?.interest ?? '')));
    if (!label || !Array.isArray(t.ids)) continue;
    const ids = [...new Set(t.ids.map(String).filter((id) => allowed.has(id)))].slice(0, 2);
    if (ids.length) tags[label] = ids;
  }
  return { tags };
}
