import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand, PutCommand, GetCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { BedrockRuntimeClient, ConverseCommand } from '@aws-sdk/client-bedrock-runtime';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { findTriggeredTemplates, getTemplate, resolveTemplate, TEMPLATES } from './question-templates.mjs';
import { parseXmlEvents } from './dfl-events.mjs';

const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);
const bedrock = new BedrockRuntimeClient({ region: 'us-east-1' });
const s3 = new S3Client({ region: process.env.DFL_DATA_REGION || process.env.AWS_REGION || 'us-east-1' });

const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;
const MATCH_STATE_TABLE = process.env.MATCH_STATE_TABLE;
const QUESTIONS_TABLE = process.env.QUESTIONS_TABLE;
const WS_ENDPOINT = process.env.WS_ENDPOINT;

const MODEL_ID = 'amazon.nova-lite-v1:0';

/**
 * Question Trigger Lambda
 *
 * Receives DFL events, buffers them, detects trigger conditions,
 * waits the appropriate delay, calls Bedrock to generate a question,
 * stores it, and broadcasts to players.
 *
 * Event payload:
 * {
 *   "matchId": "DFL-MAT-111111",
 *   "roomCode": "A7X9K2",
 *   "event": { ... parsed DFL event ... },
 *   "matchInfo": { ... match metadata ... },
 *   "playerLookup": { ... },
 *   "teamLookup": { ... }
 * }
 */
// Maximum questions per match to control costs (3 kick-off + up to 22 in-play)
const MAX_QUESTIONS_PER_MATCH = 25;
// How many kick-off questions to randomly select from the kick-off pool
const KICKOFF_QUESTION_COUNT = 3;
// Minimum seconds between questions to avoid flooding (serializes the one-at-a-time UI)
const MIN_QUESTION_SPACING_MS = 20000;
// Roughly how often a notable moment becomes an AI "color" question instead of a template
const AI_QUESTION_TRIGGERS = new Set(['Goal', 'Card', 'Substitution']);

// ─── Scoring (Kahoot-style) ─────────────────────────────────────
const BASE_POINTS = 1000;            // max for an instant correct answer
const SPEED_FLOOR = 0.5;             // slowest on-time correct still earns 50% of base
const MIN_LATE_POINTS = 100;         // flat reward for a correct catch-up (late) answer
const BONUS_SCALE = 0.5;             // AI "color" questions worth half (non-ranking flavour)
const CHANGE_PENALTY_FRACTION = 0.2; // each kick-off answer change costs 20% (compounding)
const CATCHUP_GRACE_SECONDS = 20;    // window after the live timer where late answers are accepted

/** Loose equality for answer strings (casing/whitespace/punctuation tolerant). */
function answersEqual(a, b) {
  if (a == null || b == null) return false;
  const norm = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
  return norm(a) === norm(b);
}

/**
 * Kahoot-style points for one player's pick.
 * opts: { elapsedMs, timeLimit, late, changeCount, scoring }
 *  - on-time correct  -> BASE * (1 - 0.5 * elapsed/timeLimit), i.e. fast≈BASE, slow≈BASE/2
 *  - late correct      -> flat MIN_LATE_POINTS (catch-up)
 *  - wrong             -> 0
 *  - bonus questions    -> scaled by BONUS_SCALE, never penalised below 0
 *  - kick-off changes   -> reduce earned points by CHANGE_PENALTY_FRACTION per change
 */
function scorePick(pick, correctAnswer, scoring, opts = {}) {
  if (!answersEqual(pick, correctAnswer)) return 0;

  const scale = scoring === 'bonus' ? BONUS_SCALE : 1;

  let pts;
  if (opts.late) {
    pts = MIN_LATE_POINTS * scale;
  } else {
    const timeLimit = opts.timeLimit || 15;
    const elapsedSec = Math.max(0, (opts.elapsedMs || 0) / 1000);
    const frac = Math.min(elapsedSec / timeLimit, 1); // 0 (instant) .. 1 (at buzzer)
    const speedMultiplier = 1 - (1 - SPEED_FLOOR) * frac; // 1.0 .. SPEED_FLOOR
    pts = BASE_POINTS * scale * speedMultiplier;
  }

  // Kick-off answer changes erode the score (compounding).
  if (opts.changeCount) {
    pts *= Math.pow(1 - CHANGE_PENALTY_FRACTION, opts.changeCount);
  }

  return Math.max(Math.round(pts), opts.late ? Math.round(MIN_LATE_POINTS * scale) : 1);
}

export const handler = async (event) => {
  try {
    // Route to resolution handler if flagged
    if (event.resolve) {
      return resolveQuestions(event);
    }

    // Route to reset handler if flagged — wipes prior questions + match state so
    // the same match can be demoed repeatedly with a fresh kick-off sequence.
    if (event.reset) {
      return resetMatch(event);
    }

    const { matchId, roomCode, event: dflEvent, matchInfo, playerLookup, teamLookup } = event;

    if (!matchId || !dflEvent) {
      return { statusCode: 400, body: 'matchId and event required' };
    }

    // 1. Buffer the event (always, for context + resolution)
    await bufferEvent(matchId, dflEvent);

    // 1b. Live resolution sweep — resolve any now-answerable questions and
    //     broadcast per-question results so scoring happens in real time.
    try {
      await runResolutionSweep({ matchId, roomCode, matchInfo, playerLookup, teamLookup });
    } catch (e) {
      console.error('Resolution sweep error:', e.message);
    }

    // 2. Load match state (flags: kickoffFired, aiTurn)
    const state = await getMatchState(matchId);
    const ctx = buildContext(matchInfo, playerLookup, teamLookup);

    // 3. Find deterministic templates triggered by this event
    const templates = findTriggeredTemplates(dflEvent, state);

    // On the first kick-off, queue all kick-off questions to be released
    // one-per-spacing-window over the opening minutes.
    let kickoffQueue = state.kickoffQueue || [];
    if (dflEvent.eventType === 'KickOff' && !state.kickoffFired) {
      kickoffQueue = kickoffTemplateIds();
    }

    // Decide whether this moment should be an AI "color" question instead.
    const aiEligible = AI_QUESTION_TRIGGERS.has(dflEvent.eventType);

    const realtimeTemplates = templates.filter((t) => t.section !== 'kickoff');

    if (kickoffQueue.length === 0 && realtimeTemplates.length === 0 && !aiEligible) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'no template / not AI-eligible' }) };
    }

    // 4. Max-questions cap
    const existingQuestions = await getQuestionCount(matchId).catch(() => 0);
    if (existingQuestions >= MAX_QUESTIONS_PER_MATCH) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'max questions reached' }) };
    }

    // 5. Spacing gate — one question at a time
    const lastQuestionTime = await getLastQuestionTime(matchId).catch(() => null);
    if (lastQuestionTime && (Date.now() - lastQuestionTime) < MIN_QUESTION_SPACING_MS) {
      // Persist the (possibly newly-initialised) kickoff queue + kickoffFired so it isn't lost.
      if (dflEvent.eventType === 'KickOff' && !state.kickoffFired) {
        await updateMatchFlags(matchId, { kickoffFired: true, kickoffQueue });
      }
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'too soon' }) };
    }

    // 6. Choose source. Kick-off questions drain first (opening phase),
    //    then alternate realtime template / AI for variety.
    let stored;
    let nextKickoffQueue = kickoffQueue;
    let source = 'template';

    if (kickoffQueue.length > 0) {
      const template = getTemplate(kickoffQueue[0]);
      nextKickoffQueue = kickoffQueue.slice(1);
      source = 'kickoff';
      stored = await buildAndStoreTemplateQuestion({ matchId, template, dflEvent, ctx });
    } else {
      const useAI = aiEligible && (realtimeTemplates.length === 0 || state.aiTurn === true);
      if (useAI) {
        source = 'ai';
        stored = await buildAndStoreAiQuestion({ matchId, dflEvent, ctx });
      } else {
        const template = pickTemplate(realtimeTemplates);
        source = 'template';
        stored = await buildAndStoreTemplateQuestion({ matchId, template, dflEvent, ctx });
      }
    }

    if (!stored) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'build failed' }) };
    }

    // 7. Persist rotation + kickoff state.
    await updateMatchFlags(matchId, {
      aiTurn: !state.aiTurn,
      kickoffFired: state.kickoffFired || dflEvent.eventType === 'KickOff',
      kickoffQueue: nextKickoffQueue,
    });

    // 8. Broadcast
    const targetRoom = roomCode || `match_${matchId}`;
    await broadcastQuestion(targetRoom, stored.question, stored.questionId, { type: stored.triggerType });

    return {
      statusCode: 200,
      body: JSON.stringify({ triggered: true, questionId: stored.questionId, source, templateId: stored.templateId || null }),
    };
  } catch (err) {
    console.error('Question trigger error:', err);
    return { statusCode: 500, body: err.message };
  }
};

// ─── Question Builders ──────────────────────────────────────────

/** Choose one template when several fire at once. Kick-off > immediate > deferred > endOfMatch. */
function pickTemplate(templates) {
  const rank = (t) => {
    if (t.section === 'kickoff') return 0;
    return 1;
  };
  return [...templates].sort((a, b) => rank(a) - rank(b))[0];
}

/** Build a deterministic template question, optionally enrich phrasing with Bedrock, and store it. */
async function buildAndStoreTemplateQuestion({ matchId, template, dflEvent, ctx }) {
  const built = template.build(dflEvent, ctx);
  if (!built || !built.text || !built.options) return null;

  // Optional AI phrasing pass — never changes options or the resolver/answer.
  let text = built.text;
  try {
    const enriched = await enrichPhrasing(built.text, built.options, dflEvent, ctx);
    if (enriched) text = enriched;
  } catch (e) {
    console.error('enrichPhrasing failed, using template text:', e.message);
  }

  const questionId = `q_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const item = {
    matchId,
    questionId,
    templateId: template.id,
    question: text,
    options: built.options,
    category: template.section,
    scoring: template.scoring,
    timeLimit: built.timeLimit || 15,
    resolutionType: built.resolutionType,
    knownAnswer: built.knownAnswer ?? null,
    resolverParams: built.resolverParams || {},
    correctAnswer: built.resolutionType === 'immediate' ? (built.knownAnswer ?? null) : null,
    status: built.resolutionType === 'immediate' ? 'answerKnown' : 'pending',
    triggerType: dflEvent.eventType,
    triggerEvent: dflEvent.summary || '',
    aiGenerated: false,
    userPicks: {},
    createdAt: new Date().toISOString(),
    ttl: Math.floor(Date.now() / 1000) + 86400,
  };

  await ddb.send(new PutCommand({ TableName: QUESTIONS_TABLE, Item: item }));
  console.log(`Template question stored: ${template.id} "${text}"`);
  return { questionId, question: { question: text, options: built.options, timeLimit: item.timeLimit, category: item.category }, templateId: template.id, triggerType: dflEvent.eventType };
}

/** Build a standalone AI-generated "color" question (bonus scoring, AI-resolved at match end). */
async function buildAndStoreAiQuestion({ matchId, dflEvent, ctx }) {
  const trigger = { type: dflEvent.eventType, delayMs: 0 };
  const context = await getMatchContext(matchId);
  // Pass real team names into the prompt (override the anonymised matchInfo).
  const namedMatchInfo = {
    ...ctx.matchInfo,
    homeTeamName: ctx.homeTeamName,
    guestTeamName: ctx.awayTeamName,
    competitionName: ctx.matchInfo?.competitionName || 'Bundesliga',
  };
  const question = await callBedrock(trigger, dflEvent, context, namedMatchInfo, ctx.playerLookup, ctx.teamLookup);
  if (!question || !question.question || !question.options) {
    console.error('Bedrock returned invalid AI question');
    return null;
  }

  const questionId = `q_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const item = {
    matchId,
    questionId,
    templateId: null,
    question: question.question,
    options: question.options,
    category: question.category || 'live',
    scoring: 'bonus', // AI-resolved → never affects ranked leaderboard
    difficulty: question.difficulty || 'medium',
    timeLimit: question.timeLimit || 15,
    resolutionType: question.resolutionType || 'endOfMatch',
    resolutionCriteria: question.resolutionCriteria || '',
    correctAnswer: null,
    status: 'pending',
    triggerType: dflEvent.eventType,
    triggerEvent: dflEvent.summary || '',
    aiGenerated: true,
    userPicks: {},
    createdAt: new Date().toISOString(),
    ttl: Math.floor(Date.now() / 1000) + 86400,
  };

  await ddb.send(new PutCommand({ TableName: QUESTIONS_TABLE, Item: item }));
  console.log(`AI question stored: "${question.question}"`);
  return { questionId, question, triggerType: dflEvent.eventType };
}

/**
 * End-of-match resolution handler.
 * Resolves template questions deterministically and AI questions via Bedrock.
 */
export const resolveQuestions = async (event) => {
  try {
    const { matchId, roomCode, matchSummary } = event;
    if (!matchId) return { statusCode: 400, body: 'matchId required' };

    // 1. Get all unresolved questions (pending or answerKnown)
    const result = await ddb.send(new QueryCommand({
      TableName: QUESTIONS_TABLE,
      KeyConditionExpression: 'matchId = :matchId',
      FilterExpression: '#s <> :resolved',
      ExpressionAttributeNames: { '#s': 'status' },
      ExpressionAttributeValues: { ':matchId': matchId, ':resolved': 'resolved' },
    }));

    const unresolved = result.Items || [];
    if (unresolved.length === 0) {
      return { statusCode: 200, body: JSON.stringify({ resolved: 0 }) };
    }

    console.log(`Resolving ${unresolved.length} questions for match ${matchId}`);

    // Prefer the full, exact event log re-parsed from S3 (accurate aggregates).
    // Fall back to the buffered rolling window if keys aren't provided.
    let events = await loadFullEventLog(event, matchId);
    if (!events || events.length === 0) {
      events = await getMatchContext(matchId);
    }
    const ctx = buildContext(
      event.matchSummary || null,
      event.playerLookup,
      event.teamLookup
    );

    // 2. Split deterministic (template) vs AI questions
    const templateQs = unresolved.filter((q) => q.templateId);
    const aiQs = unresolved.filter((q) => !q.templateId);

    const resolutions = [];

    // 2a. Deterministic resolution — fair, code-only
    for (const q of templateQs) {
      const answer = q.knownAnswer ?? resolveTemplate(q, events, ctx);
      if (answer == null) continue; // not resolvable (shouldn't happen at match end)
      resolutions.push({ questionId: q.questionId, correctAnswer: answer });
    }

    // 2b. AI resolution — only for bonus AI questions
    if (aiQs.length > 0) {
      try {
        const aiResolutions = await resolveWithBedrock(aiQs, events, matchSummary);
        resolutions.push(...aiResolutions);
      } catch (e) {
        console.error('AI resolution failed:', e.message);
      }
    }

    // 3. Persist correct answers + per-player scores
    for (const r of resolutions) {
      const original = unresolved.find((q) => q.questionId === r.questionId);
      if (!original) continue;
      const scores = computeScores(original, r.correctAnswer);
      await ddb.send(new PutCommand({
        TableName: QUESTIONS_TABLE,
        Item: { ...original, correctAnswer: r.correctAnswer, scores, status: 'resolved', resolvedAt: new Date().toISOString() },
      }));
    }

    // 4. Recompute the authoritative leaderboard and broadcast final results.
    const leaderboard = await computeLeaderboard(matchId);
    const targetRoom = roomCode || `match_${matchId}`;
    await broadcastResolutions(targetRoom, resolutions, unresolved, leaderboard);

    return { statusCode: 200, body: JSON.stringify({ resolved: resolutions.length }) };
  } catch (err) {
    console.error('Resolution error:', err);
    return { statusCode: 500, body: err.message };
  }
};

// ─── Live Resolution Sweep & Scoring ────────────────────────────

/**
 * Resolve every question that has become answerable, score it, and broadcast
 * a per-question result. Driven by the event stream so no extra scheduler is
 * needed. Idempotent: a question is only resolved/scored once (status -> resolved).
 */
async function runResolutionSweep({ matchId, roomCode, matchInfo, playerLookup, teamLookup }) {
  const result = await ddb.send(new QueryCommand({
    TableName: QUESTIONS_TABLE,
    KeyConditionExpression: 'matchId = :m',
    FilterExpression: '#s <> :resolved',
    ExpressionAttributeNames: { '#s': 'status' },
    ExpressionAttributeValues: { ':m': matchId, ':resolved': 'resolved' },
  }));
  const open = result.Items || [];
  if (open.length === 0) return;

  const events = await getMatchContext(matchId);
  const ctx = buildContext(matchInfo, playerLookup, teamLookup);

  const resolvedNow = [];
  for (const q of open) {
    // endOfMatch questions (kick-off aggregates, AI color) wait for the whistle.
    if (q.resolutionType === 'endOfMatch') continue;

    // Keep the question open for its answer window + catch-up grace so players
    // (including those who missed it live) have time to answer before scoring.
    const createdMs = q.createdAt ? new Date(q.createdAt).getTime() : 0;
    const openMs = ((q.timeLimit || 15) + CATCHUP_GRACE_SECONDS) * 1000;
    if (createdMs && Date.now() - createdMs < openMs) continue;

    const answer = q.knownAnswer ?? resolveTemplate(q, events, ctx);
    if (answer == null) continue; // not yet resolvable (e.g. deferred window still open)

    // Conditional write resolves exactly once even under concurrent invocations.
    const scores = computeScores(q, answer);
    try {
      await ddb.send(new PutCommand({
        TableName: QUESTIONS_TABLE,
        Item: { ...q, correctAnswer: answer, scores, status: 'resolved', resolvedAt: new Date().toISOString() },
        ConditionExpression: '#s <> :resolved',
        ExpressionAttributeNames: { '#s': 'status' },
        ExpressionAttributeValues: { ':resolved': 'resolved' },
      }));
      resolvedNow.push({ questionId: q.questionId, correctAnswer: answer });
    } catch (err) {
      if (err.name !== 'ConditionalCheckFailedException') throw err;
      // Another invocation resolved it first — skip.
    }
  }

  if (resolvedNow.length === 0) return;

  const leaderboard = await computeLeaderboard(matchId);
  const targetRoom = roomCode || `match_${matchId}`;
  await broadcastResolutions(targetRoom, resolvedNow, open, leaderboard);
  console.log(`Live-resolved ${resolvedNow.length} question(s)`);
}

/** Compute per-player points for a resolved question. Returns { userId: points }. */
function computeScores(question, correctAnswer) {
  const picks = question.userPicks || {};
  const scoring = question.scoring || 'ranked';
  const timeLimit = question.timeLimit || 15;
  const createdMs = question.createdAt ? new Date(question.createdAt).getTime() : null;
  const out = {};

  for (const [userId, pickData] of Object.entries(picks)) {
    const pick = typeof pickData === 'string' ? pickData : pickData.pick;
    const changeCount = (typeof pickData === 'object' && pickData.changeCount) || 0;

    // Server-authoritative elapsed time: prefer the answer's own timestamp,
    // fall back to the client-reported secondsTaken.
    let elapsedMs = null;
    if (typeof pickData === 'object' && pickData.answeredAt && createdMs) {
      elapsedMs = new Date(pickData.answeredAt).getTime() - createdMs;
    } else if (typeof pickData === 'object' && pickData.secondsTaken != null) {
      elapsedMs = pickData.secondsTaken * 1000;
    }

    // A pick is "late" (catch-up) if it landed after the live answer window.
    const late = elapsedMs != null && elapsedMs > timeLimit * 1000;

    out[userId] = scorePick(pick, correctAnswer, scoring, {
      elapsedMs: elapsedMs ?? 0,
      timeLimit,
      late,
      changeCount,
    });
  }
  return out;
}

/** Sum each player's scores across all resolved questions for an authoritative leaderboard. */
async function computeLeaderboard(matchId) {
  const result = await ddb.send(new QueryCommand({
    TableName: QUESTIONS_TABLE,
    KeyConditionExpression: 'matchId = :m',
    ExpressionAttributeValues: { ':m': matchId },
  }));
  const totals = {};
  for (const q of result.Items || []) {
    const scores = q.scores || {};
    for (const [userId, pts] of Object.entries(scores)) {
      totals[userId] = (totals[userId] || 0) + (pts || 0);
    }
  }
  return totals; // { userId: totalXP }
}

// ─── Match Context & State ──────────────────────────────────────

/**
 * Re-parse the full match event log from S3 for accurate end-of-match resolution.
 * Returns [] when bucket/eventsKey are not supplied (caller falls back to buffer).
 */
async function loadFullEventLog(event, matchId) {
  const bucket = event.bucket || process.env.DFL_DATA_BUCKET;
  const eventsKey = event.eventsKey;
  if (!bucket || !eventsKey) return [];
  try {
    const resp = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: eventsKey }));
    const xml = await resp.Body.transformToString();
    const events = parseXmlEvents(xml, matchId, event.playerLookup || {}, event.teamLookup || {});
    console.log(`Resolver re-parsed ${events.length} events from S3`);
    return events;
  } catch (err) {
    console.error('loadFullEventLog error:', err.message);
    return [];
  }
}

/**
 * The hackathon match data is anonymised ("FC Team" vs "Club") — no real club
 * names exist in any field (only the positions/KPI *filenames* say
 * "Bayern_Hamburg"). So we map anonymised names/ids to the real fixture.
 *
 * Configurable per deployment via the TEAM_NAME_OVERRIDES env var (JSON), e.g.
 *   {"DFL-CLU-000001":"Bayern Munich","DFL-CLU-000002":"Hamburger SV"}
 * Falls back to the known default for this match file.
 */
const DEFAULT_TEAM_NAME_OVERRIDES = {
  'FC Team': 'Bayern Munich',
  'Club': 'Hamburger SV',
  'DFL-CLU-000001': 'Bayern Munich',
  'DFL-CLU-000002': 'Hamburger SV',
};

const TEAM_NAME_OVERRIDES = (() => {
  try {
    if (process.env.TEAM_NAME_OVERRIDES) {
      return { ...DEFAULT_TEAM_NAME_OVERRIDES, ...JSON.parse(process.env.TEAM_NAME_OVERRIDES) };
    }
  } catch (e) {
    console.error('Invalid TEAM_NAME_OVERRIDES env, using defaults:', e.message);
  }
  return DEFAULT_TEAM_NAME_OVERRIDES;
})();

function realTeamName(name, id) {
  return TEAM_NAME_OVERRIDES[id] || TEAM_NAME_OVERRIDES[name] || name || 'Team';
}

/** Normalise match info into a resolver context with team ids/names. */
function buildContext(matchInfo, playerLookup, teamLookup) {
  const mi = matchInfo || {};
  const homeTeamId = mi.homeTeamId || mi.HomeTeamId || null;
  const awayTeamId = mi.guestTeamId || mi.GuestTeamId || null;
  const homeRaw = mi.homeTeamName || mi.HomeTeamName || 'Home';
  const awayRaw = mi.guestTeamName || mi.GuestTeamName || 'Away';

  // Apply real-name overrides to the team lookup so event summaries also benefit.
  const lookup = { ...(teamLookup || mi.teamLookup || {}) };
  for (const [id, t] of Object.entries(lookup)) {
    const real = realTeamName(t.teamName || t.shortName, id);
    lookup[id] = { ...t, teamName: real, shortName: real };
  }

  return {
    matchInfo: mi,
    homeTeamId,
    awayTeamId,
    homeTeamName: realTeamName(homeRaw, homeTeamId),
    awayTeamName: realTeamName(awayRaw, awayTeamId),
    playerLookup: playerLookup || mi.playerLookup || {},
    teamLookup: lookup,
  };
}

/**
 * Reset all per-match state so a match can be re-demoed cleanly: deletes every
 * stored question and clears the match-state flags (kickoffFired / kickoffQueue).
 */
async function resetMatch(event) {
  const { matchId } = event;
  if (!matchId) return { statusCode: 400, body: 'matchId required' };
  try {
    // 1. Delete all questions for this match.
    const qs = await ddb.send(new QueryCommand({
      TableName: QUESTIONS_TABLE,
      KeyConditionExpression: 'matchId = :m',
      ExpressionAttributeValues: { ':m': matchId },
    }));
    for (const q of qs.Items || []) {
      await ddb.send(new DeleteCommand({
        TableName: QUESTIONS_TABLE,
        Key: { matchId, questionId: q.questionId },
      }));
    }

    // 2. Clear match-state flags.
    await ddb.send(new DeleteCommand({
      TableName: MATCH_STATE_TABLE,
      Key: { matchId },
    }));

    console.log(`Reset match ${matchId}: removed ${qs.Items?.length || 0} questions`);
    return { statusCode: 200, body: JSON.stringify({ reset: true, removed: qs.Items?.length || 0 }) };
  } catch (err) {
    console.error('resetMatch error:', err.message);
    return { statusCode: 500, body: err.message };
  }
}

async function getMatchState(matchId) {
  try {
    const result = await ddb.send(new GetCommand({ TableName: MATCH_STATE_TABLE, Key: { matchId } }));
    const item = result.Item || {};
    return {
      kickoffFired: item.kickoffFired === true,
      aiTurn: item.aiTurn === true,
      kickoffQueue: Array.isArray(item.kickoffQueue) ? item.kickoffQueue : [],
    };
  } catch {
    return { kickoffFired: false, aiTurn: false, kickoffQueue: [] };
  }
}

/** Randomly select KICKOFF_QUESTION_COUNT kick-off template ids from the pool. */
function kickoffTemplateIds() {
  const pool = TEMPLATES.filter((t) => t.section === 'kickoff').map((t) => t.id);
  // Fisher–Yates shuffle, then take the first N.
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, KICKOFF_QUESTION_COUNT);
}

async function updateMatchFlags(matchId, flags) {
  try {
    const existing = await ddb.send(new GetCommand({ TableName: MATCH_STATE_TABLE, Key: { matchId } }));
    const item = existing.Item || { matchId };
    await ddb.send(new PutCommand({
      TableName: MATCH_STATE_TABLE,
      Item: { ...item, ...flags, ttl: Math.floor(Date.now() / 1000) + 7200 },
    }));
  } catch (err) {
    console.error('updateMatchFlags error:', err.message);
  }
}

// ─── Question Rate Limiting ─────────────────────────────────────

async function getQuestionCount(matchId) {
  try {
    const result = await ddb.send(new QueryCommand({
      TableName: QUESTIONS_TABLE,
      KeyConditionExpression: 'matchId = :matchId',
      ExpressionAttributeValues: { ':matchId': matchId },
      Select: 'COUNT',
    }));
    return result.Count || 0;
  } catch (err) {
    console.error('getQuestionCount error:', err.message);
    return 0;
  }
}

async function getLastQuestionTime(matchId) {
  try {
    const result = await ddb.send(new QueryCommand({
      TableName: QUESTIONS_TABLE,
      KeyConditionExpression: 'matchId = :matchId',
      ExpressionAttributeValues: { ':matchId': matchId },
      ScanIndexForward: false,
      Limit: 1,
    }));
    if (result.Items && result.Items.length > 0) {
      return new Date(result.Items[0].createdAt).getTime();
    }
    return null;
  } catch (err) {
    console.error('getLastQuestionTime error:', err.message);
    return null;
  }
}

// ─── Bedrock Integration ────────────────────────────────────────

/**
 * Optional phrasing enrichment for a deterministic template question.
 * Bedrock may ONLY rewrite the question text — it must not change the options
 * or the answer. Returns null on any failure so the caller falls back to the
 * template text. This keeps ranked scoring fully deterministic.
 */
async function enrichPhrasing(text, options, dflEvent, ctx) {
  const systemPrompt = `You rewrite a live football quiz question to be punchier and more exciting.
STRICT RULES:
- Keep the SAME meaning and the SAME answer options: ${JSON.stringify(options)}
- Do NOT add new options or change what is being asked.
- Return ONLY the rewritten question text, one line, no quotes, no JSON.`;

  const userMessage = JSON.stringify({
    original: text,
    options,
    moment: {
      type: dflEvent.eventType,
      player: dflEvent.playerName || null,
      team: dflEvent.teamName || null,
      minute: dflEvent.eventTime || null,
    },
    match: { home: ctx.homeTeamName, away: ctx.awayTeamName },
  });

  const response = await bedrock.send(new ConverseCommand({
    modelId: MODEL_ID,
    inferenceConfig: { maxTokens: 80, temperature: 0.7 },
    system: [{ text: systemPrompt }],
    messages: [{ role: 'user', content: [{ text: userMessage }] }],
  }));

  const out = (response.output?.message?.content?.[0]?.text || '').trim();
  // Sanity guard: reject empty or absurdly long rewrites.
  if (!out || out.length > 160) return null;
  return out.replace(/^["']|["']$/g, '');
}

async function callBedrock(trigger, dflEvent, recentEvents, matchInfo, playerLookup, teamLookup) {
  const match = matchInfo || {};
  const playerName = dflEvent.playerName || resolvePlayer(dflEvent.playerId, playerLookup);
  const teamName = dflEvent.teamName || resolveTeam(dflEvent.teamId, teamLookup);

  const systemPrompt = `You are a live football prediction quiz generator for the Bundesliga.
Generate engaging multiple-choice questions based on real-time match events.
Questions must be PREDICTIVE (what happens NEXT), not about what already happened.

Rules:
- Choose 2-4 options depending on the question complexity
- Set a time limit (10-20 seconds) based on how quickly a fan could decide
- Determine if the answer can be resolved immediately (within the next few events) or must wait until match end
- Return ONLY valid JSON, no other text

Required JSON format:
{
  "question": "string",
  "options": ["string", ...],
  "category": "string",
  "difficulty": "easy|medium|hard",
  "timeLimit": number,
  "resolutionType": "immediate|deferred",
  "resolutionCriteria": "string describing how to determine the correct answer"
}`;

  const userMessage = JSON.stringify({
    match: {
      competition: match.competitionName || 'Bundesliga',
      homeTeam: match.homeTeamName || 'Home',
      awayTeam: match.guestTeamName || 'Away',
      score: match.result || '0-0',
      minute: dflEvent.gameTime || dflEvent.eventTime || '?',
      stadium: match.stadiumName || '',
    },
    trigger: {
      type: trigger.type,
      team: teamName,
      player: playerName,
      details: dflEvent.summary || '',
    },
    recentEvents: recentEvents.slice(-10).map(e => ({
      type: e.eventType,
      player: e.player,
      team: e.team,
      evaluation: e.evaluation,
      summary: e.summary,
    })),
  });

  const payload = {
    inferenceConfig: { maxTokens: 512 },
    system: [{ text: systemPrompt }],
    messages: [{ role: 'user', content: [{ text: userMessage }] }],
  };

  const response = await bedrock.send(new ConverseCommand({
    modelId: MODEL_ID,
    inferenceConfig: { maxTokens: 512 },
    system: [{ text: systemPrompt }],
    messages: [{ role: 'user', content: [{ text: userMessage }] }],
  }));

  const content = response.output?.message?.content?.[0]?.text || '';

  // Parse JSON from response (handle potential markdown wrapping)
  const jsonMatch = content.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    console.error('Could not parse JSON from Bedrock response:', content);
    return null;
  }

  try {
    return JSON.parse(jsonMatch[0]);
  } catch (e) {
    console.error('JSON parse error:', e, 'Content:', jsonMatch[0]);
    return null;
  }
}

async function resolveWithBedrock(pendingQuestions, matchEvents, matchSummary) {
  const systemPrompt = `You are resolving prediction questions from a completed Bundesliga match.
For each question, determine the correct answer based on what actually happened in the match.
Return ONLY valid JSON array.

Required format:
[
  { "questionId": "string", "correctAnswer": "string (must be one of the original options)" }
]`;

  const userMessage = JSON.stringify({
    matchSummary: matchSummary || {},
    matchEvents: matchEvents.slice(-50),
    questions: pendingQuestions.map(q => ({
      questionId: q.questionId,
      question: q.question,
      options: q.options,
      resolutionCriteria: q.resolutionCriteria,
      triggerEvent: q.triggerEvent,
    })),
  });

  const payload = {
    inferenceConfig: { maxTokens: 1024 },
    system: [{ text: systemPrompt }],
    messages: [{ role: 'user', content: [{ text: userMessage }] }],
  };

  const response = await bedrock.send(new ConverseCommand({
    modelId: MODEL_ID,
    inferenceConfig: { maxTokens: 1024 },
    system: [{ text: systemPrompt }],
    messages: [{ role: 'user', content: [{ text: userMessage }] }],
  }));

  const content = response.output?.message?.content?.[0]?.text || '';

  const jsonMatch = content.match(/\[[\s\S]*\]/);
  if (!jsonMatch) {
    console.error('Could not parse resolution JSON:', content);
    return [];
  }

  try {
    const parsed = JSON.parse(jsonMatch[0]);
    // Snap each AI answer to an actual option string so exact-match scoring works.
    return parsed.map((r) => {
      const q = pendingQuestions.find((q) => q.questionId === r.questionId);
      const snapped = q ? snapToOption(r.correctAnswer, q.options) : r.correctAnswer;
      return { ...r, correctAnswer: snapped };
    }).filter((r) => r.correctAnswer != null);
  } catch (e) {
    console.error('Resolution JSON parse error:', e);
    return [];
  }
}

/**
 * Match an AI-produced answer string to one of the real option strings,
 * tolerating casing/whitespace/punctuation differences. Falls back to a
 * contains-match, else null (so we don't store an unmatchable answer).
 */
function snapToOption(answer, options = []) {
  if (!answer || options.length === 0) return answer ?? null;
  const norm = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
  const a = norm(answer);
  // Exact normalised match.
  const exact = options.find((o) => norm(o) === a);
  if (exact) return exact;
  // Containment either direction (e.g. "Bayern" vs "Bayern Munich").
  const partial = options.find((o) => norm(o).includes(a) || a.includes(norm(o)));
  return partial ?? null;
}

async function bufferEvent(matchId, event) {
  try {
    const existing = await ddb.send(new GetCommand({
      TableName: MATCH_STATE_TABLE,
      Key: { matchId },
    }));

    let events = existing.Item?.recentEvents || [];
    events.push({
      eventId: event.eventId || '',
      eventType: event.eventType || '',
      subType: event.subType || null,
      teamId: event.teamId || null,
      playerId: event.playerId || null,
      playerInId: event.playerInId || null,
      assistId: event.assistId || null,
      cardColor: event.cardColor || null,
      insideBox: event.insideBox ?? null,
      evaluation: event.evaluation || null,
      eventTime: event.eventTime || null,
      gameSection: event.gameSection || null,
      xPosition: event.xPosition || 0,
      // human-friendly extras (used by AI resolver / summaries)
      team: event.teamName || event.teamId || null,
      player: event.playerName || event.playerId || null,
      summary: event.summary || '',
    });

    // Keep a large rolling window so end-of-match aggregate resolvers
    // (total passes/corners/goals) have enough history. The full, exact log
    // is re-parsed from S3 at resolution time when keys are available.
    if (events.length > 2000) events = events.slice(-2000);

    await ddb.send(new PutCommand({
      TableName: MATCH_STATE_TABLE,
      Item: {
        matchId,
        recentEvents: events,
        lastUpdated: new Date().toISOString(),
        ttl: Math.floor(Date.now() / 1000) + 7200,
      },
    }));
  } catch (err) {
    console.error('Buffer event error:', err.message || err);
  }
}

async function getMatchContext(matchId) {
  try {
    const result = await ddb.send(new GetCommand({
      TableName: MATCH_STATE_TABLE,
      Key: { matchId },
    }));
    return result.Item?.recentEvents || [];
  } catch (err) {
    return [];
  }
}

// ─── WebSocket Broadcast ────────────────────────────────────────

async function broadcastQuestion(roomCode, question, questionId, trigger) {
  const connections = await getConnections(roomCode);
  if (connections.length === 0) return;

  const message = {
    action: 'prediction_question',
    data: {
      questionId,
      question: question.question,
      options: question.options,
      category: question.category,
      difficulty: question.difficulty,
      timeLimit: question.timeLimit,
      resolutionType: question.resolutionType,
      triggerType: trigger.type,
      timestamp: new Date().toISOString(),
    },
  };

  await broadcastToConnections(connections, message);
  console.log(`Question broadcast to ${connections.length} connections`);
}

async function broadcastResolutions(roomCode, resolutions, questions, leaderboard = {}) {
  const connections = await getConnections(roomCode);
  if (connections.length === 0) return;

  const results = resolutions.map(r => {
    const q = questions.find(q => q.questionId === r.questionId);
    return {
      questionId: r.questionId,
      question: q?.question || '',
      correctAnswer: r.correctAnswer,
      userPicks: q?.userPicks || {},
      scores: q?.scores || {},
      scoring: q?.scoring || 'ranked',
      category: q?.category || 'live',
      aiGenerated: q?.aiGenerated === true,
    };
  });

  const message = {
    action: 'questions_resolved',
    data: { results, leaderboard },
  };

  await broadcastToConnections(connections, message);
  console.log(`Resolutions broadcast: ${resolutions.length} questions`);
}

async function getConnections(roomCode) {
  const result = await ddb.send(new ScanCommand({
    TableName: CONNECTIONS_TABLE,
    FilterExpression: 'roomCode = :roomCode',
    ExpressionAttributeValues: { ':roomCode': roomCode },
  }));
  return result.Items || [];
}

async function broadcastToConnections(connections, message) {
  if (!WS_ENDPOINT) return;
  const apiClient = new ApiGatewayManagementApiClient({ endpoint: WS_ENDPOINT });
  const payload = Buffer.from(JSON.stringify(message));

  await Promise.all(connections.map(async (conn) => {
    try {
      await apiClient.send(new PostToConnectionCommand({
        ConnectionId: conn.connectionId,
        Data: payload,
      }));
    } catch (err) {
      if (err.statusCode === 410 || err.$metadata?.httpStatusCode === 410) {
        await ddb.send(new DeleteCommand({
          TableName: CONNECTIONS_TABLE,
          Key: { connectionId: conn.connectionId },
        }));
      }
    }
  }));
}

// ─── Utilities ──────────────────────────────────────────────────

function resolvePlayer(playerId, lookup) {
  if (!playerId || !lookup?.[playerId]) return playerId || 'Unknown';
  return lookup[playerId].shortName || `${lookup[playerId].firstName} ${lookup[playerId].lastName}`;
}

function resolveTeam(teamId, lookup) {
  if (!teamId || !lookup?.[teamId]) return teamId || 'Unknown';
  return lookup[teamId].shortName || lookup[teamId].teamName;
}

function randomBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function sleep(ms) {
  if (ms <= 0) return Promise.resolve();
  return new Promise(resolve => setTimeout(resolve, ms));
}
