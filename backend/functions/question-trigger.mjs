import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand, PutCommand, GetCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { BedrockRuntimeClient, ConverseCommand } from '@aws-sdk/client-bedrock-runtime';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { findTriggeredTemplates, getTemplate, resolveTemplate, TEMPLATES, templateDimension, templateCap } from './question-templates.mjs';
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
// Demo mode: a short, fast game for presentations.
const DEMO_MAX_QUESTIONS = 5;
const DEMO_QUESTION_SPACING_MS = 8000;
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

    const { matchId, roomCode, event: dflEvent, matchInfo, playerLookup, teamLookup, demoMode = false } = event;

    if (!matchId || !dflEvent) {
      return { statusCode: 400, body: 'matchId and event required' };
    }

    // Demo mode tightens the limits for short, fast presentations.
    const maxQuestions = demoMode ? DEMO_MAX_QUESTIONS : MAX_QUESTIONS_PER_MATCH;
    const questionSpacingMs = demoMode ? DEMO_QUESTION_SPACING_MS : MIN_QUESTION_SPACING_MS;

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
    // one-per-spacing-window over the opening minutes. Guard against replays
    // re-entering this branch (kickoffFired short-circuits re-queueing).
    let kickoffQueue = state.kickoffQueue || [];
    if (dflEvent.eventType === 'KickOff' && !state.kickoffFired) {
      kickoffQueue = kickoffTemplateIds();
      // In demo mode, keep only 2 kick-off questions so in-play moments still fit the 5-question budget.
      if (demoMode) kickoffQueue = kickoffQueue.slice(0, 2);
    }
    // Drop any kick-off templates that have already hit their cap (defensive
    // against replays where the queue persisted but questions were created).
    kickoffQueue = kickoffQueue.filter(
      (id) => (state.usedTemplateCounts[id] || 0) < templateCap(id)
    );

    // Decide whether this moment should be an AI "color" question instead.
    const aiEligible = AI_QUESTION_TRIGGERS.has(dflEvent.eventType);

    // Filter realtime templates: respect per-template caps, avoid back-to-back
    // repeats (recent window), and only allow a capped repeat for a DIFFERENT
    // subject (player/team) than the prior instance.
    const subject = dflEvent.playerId || dflEvent.teamId || null;
    const recentWindow = state.recentTemplateIds.slice(-4);
    const eligibleRealtime = templates
      .filter((t) => t.section !== 'kickoff')
      .filter((t) => {
        const used = state.usedTemplateCounts[t.id] || 0;
        if (used >= templateCap(t.id)) return false; // hit cap
        if (recentWindow.includes(t.id)) return false; // too recent
        // If used at least once, require a different subject than last time.
        if (used > 0) {
          const lastSubject = state.templateLastSubject[t.id];
          if (lastSubject != null && subject != null && lastSubject === subject) return false;
        }
        return true;
      });

    if (kickoffQueue.length === 0 && eligibleRealtime.length === 0 && !aiEligible) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'no eligible template / not AI-eligible' }) };
    }

    // 4. Max-questions cap
    const existingQuestions = await getQuestionCount(matchId).catch(() => 0);
    if (existingQuestions >= maxQuestions) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'max questions reached' }) };
    }

    // 5. Spacing gate — one question at a time
    const lastQuestionTime = await getLastQuestionTime(matchId).catch(() => null);
    if (lastQuestionTime && (Date.now() - lastQuestionTime) < questionSpacingMs) {
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
    let chosenTemplateId = null;

    if (kickoffQueue.length > 0) {
      const template = getTemplate(kickoffQueue[0]);
      nextKickoffQueue = kickoffQueue.slice(1);
      source = 'kickoff';
      chosenTemplateId = template?.id || null;
      stored = await buildAndStoreTemplateQuestion({ matchId, template, dflEvent, ctx });
    } else {
      const useAI = aiEligible && (eligibleRealtime.length === 0 || state.aiTurn === true);
      if (useAI) {
        source = 'ai';
        stored = await buildAndStoreAiQuestion({ matchId, dflEvent, ctx, state });
      } else {
        // Prefer the template whose dimension was used least recently (spread).
        const template = pickTemplateBySpread(eligibleRealtime, state);
        source = 'template';
        chosenTemplateId = template?.id || null;
        stored = await buildAndStoreTemplateQuestion({ matchId, template, dflEvent, ctx });
      }
    }

    if (!stored) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'build failed' }) };
    }

    // 7. Persist rotation + kickoff state + usage tracking.
    const usedTemplateId = chosenTemplateId || stored.templateId || null;
    const newCounts = { ...state.usedTemplateCounts };
    const newRecent = [...state.recentTemplateIds];
    const newDims = [...state.recentDimensions];
    const newSubjects = { ...state.templateLastSubject };
    if (usedTemplateId) {
      newCounts[usedTemplateId] = (newCounts[usedTemplateId] || 0) + 1;
      newRecent.push(usedTemplateId);
      newDims.push(templateDimension(usedTemplateId));
      if (subject != null) newSubjects[usedTemplateId] = subject;
    } else if (source === 'ai') {
      newRecent.push('__ai__');
      newDims.push(stored.question?.category || 'ai');
    }

    await updateMatchFlags(matchId, {
      aiTurn: !state.aiTurn,
      kickoffFired: state.kickoffFired || dflEvent.eventType === 'KickOff',
      kickoffQueue: nextKickoffQueue,
      usedTemplateCounts: newCounts,
      recentTemplateIds: newRecent.slice(-10),
      recentDimensions: newDims.slice(-10),
      templateLastSubject: newSubjects,
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

/**
 * Choose the eligible template whose DIMENSION has been used least recently,
 * so consecutive questions cover different aspects of play (goals, cards,
 * shots, corners, possession, discipline, player). Ties break on least-recent
 * dimension position, then deterministic-section rank.
 */
function pickTemplateBySpread(templates, state) {
  if (!templates || templates.length === 0) return null;
  if (templates.length === 1) return templates[0];

  const recentDims = state.recentDimensions || [];
  // Score each candidate by how recently its dimension was used (lower = better).
  const dimRecency = (dim) => {
    const idx = recentDims.lastIndexOf(dim);
    return idx === -1 ? -1 : idx; // -1 = never used recently (best)
  };

  return [...templates].sort((a, b) => {
    const ra = dimRecency(templateDimension(a.id));
    const rb = dimRecency(templateDimension(b.id));
    // Never-used dimensions (-1) come first; otherwise older (smaller idx) first.
    if (ra !== rb) return ra - rb;
    // Tie-break: fewer total uses first.
    const ua = state.usedTemplateCounts?.[a.id] || 0;
    const ub = state.usedTemplateCounts?.[b.id] || 0;
    return ua - ub;
  })[0];
}

/** Build a deterministic template question, optionally enrich phrasing with Bedrock, and store it. */
async function buildAndStoreTemplateQuestion({ matchId, template, dflEvent, ctx }) {
  if (!template) return null;

  // Idempotency: never create two questions for the same (template, trigger event).
  // Protects against replays / duplicate invocations re-firing the same moment.
  if (dflEvent.eventId) {
    const dup = await questionExistsFor(matchId, template.id, dflEvent.eventId);
    if (dup) {
      console.log(`Skipping duplicate ${template.id} for event ${dflEvent.eventId}`);
      return null;
    }
  }

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
    triggerEventId: dflEvent.eventId || null,
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
async function buildAndStoreAiQuestion({ matchId, dflEvent, ctx, state = {} }) {
  const trigger = { type: dflEvent.eventType, delayMs: 0 };
  const context = await getMatchContext(matchId);
  // Compute the LIVE score from events so far — never leak the final result,
  // which would make AI questions trivial/odd. This is the score at this moment.
  const live = liveMatchSnapshot(context, ctx);
  // Pass real team names into the prompt (override the anonymised matchInfo).
  // result is the LIVE score, not matchInfo.result (which is full-time).
  const namedMatchInfo = {
    ...ctx.matchInfo,
    homeTeamName: ctx.homeTeamName,
    guestTeamName: ctx.awayTeamName,
    competitionName: ctx.matchInfo?.competitionName || 'Bundesliga',
    result: live.scoreline,
    liveScore: live.scoreline,
    liveMinute: live.minute,
  };

  // Gather already-asked questions for this match so the AI avoids repeats and
  // we can reject near-duplicates after generation.
  const asked = await getAskedQuestions(matchId);
  const askedTexts = asked.map((q) => q.question).filter(Boolean);
  const usedDimensions = new Set([...(state.recentDimensions || []), ...asked.map((q) => q.category)].filter(Boolean));
  // Force the AI onto a dimension we haven't covered much.
  const allDimensions = ['goal', 'cards', 'shots', 'subs', 'momentum', 'player'];
  const preferredDimension = allDimensions.find((d) => !usedDimensions.has(d)) || allDimensions[Math.floor(Math.random() * allDimensions.length)];

  // Try up to 3 times to get a question that isn't a near-duplicate.
  let question = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    const candidate = await callBedrock(
      trigger, dflEvent, context, namedMatchInfo, ctx.playerLookup, ctx.teamLookup, live,
      { askedTexts, preferredDimension }
    );
    if (!candidate || !candidate.question || !candidate.options) continue;
    if (!isTooSimilar(candidate.question, askedTexts)) {
      question = candidate;
      break;
    }
    console.log(`AI question too similar (attempt ${attempt + 1}), regenerating: "${candidate.question}"`);
  }

  if (!question || !question.question || !question.options) {
    console.error('Bedrock returned invalid/duplicate AI question after retries');
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
    triggerEventId: dflEvent.eventId || null,
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

    // 2a. Deterministic resolution — fair, code-only.
    //     If a deferred template never saw its follow-up event, fall back to the
    //     negative/last option so the question STILL resolves to a real option
    //     (otherwise both answers would score 0). Ranked questions must always
    //     produce a valid option.
    for (const q of templateQs) {
      let answer = q.knownAnswer ?? resolveTemplate(q, events, ctx);
      if (answer == null) {
        answer = Array.isArray(q.options) && q.options.length
          ? q.options[q.options.length - 1]
          : null;
      }
      if (answer == null) continue;
      // Guarantee the answer is one of the real options.
      answer = snapToOption(answer, q.options, { fallbackToFirst: true }) ?? answer;
      resolutions.push({ questionId: q.questionId, correctAnswer: answer });
    }

    // 2b. AI resolution — only for bonus AI questions
    if (aiQs.length > 0) {
      let aiResolutions = [];
      try {
        aiResolutions = await resolveWithBedrock(aiQs, events, matchSummary);
        resolutions.push(...aiResolutions);
      } catch (e) {
        console.error('AI resolution failed:', e.message);
      }
      // Guarantee every AI question resolves to a real option even if Bedrock
      // skipped it or failed — otherwise it would score 0 for everyone.
      const resolvedIds = new Set(aiResolutions.map((r) => r.questionId));
      for (const q of aiQs) {
        if (resolvedIds.has(q.questionId)) continue;
        const fallback = Array.isArray(q.options) && q.options.length ? q.options[0] : null;
        if (fallback != null) {
          resolutions.push({ questionId: q.questionId, correctAnswer: fallback });
        }
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

/**
 * Compute a point-in-time snapshot of the match from the buffered events:
 * the live scoreline, elapsed minute, and short recent-event narrative. Used
 * to give the AI generator real, CURRENT context (never the full-time result).
 */
function liveMatchSnapshot(events = [], ctx = {}) {
  const goals = events.filter((e) => e.eventType === 'Goal');
  const homeGoals = goals.filter((g) => g.teamId === ctx.homeTeamId).length;
  const awayGoals = goals.filter((g) => g.teamId === ctx.awayTeamId).length;
  const home = ctx.homeTeamName || 'Home';
  const away = ctx.awayTeamName || 'Away';

  // Elapsed minute relative to the first kick-off.
  let minute = null;
  const ko = events.find((e) => e.eventType === 'KickOff');
  const last = events[events.length - 1];
  if (ko?.eventTime && last?.eventTime) {
    const m = (new Date(last.eventTime).getTime() - new Date(ko.eventTime).getTime()) / 60000;
    if (!Number.isNaN(m) && m >= 0) minute = Math.round(m);
  }

  // Last few meaningful moments for narrative colour.
  const notable = new Set(['Goal', 'Card', 'Substitution', 'Penalty', 'Offside']);
  const recentNarrative = events
    .filter((e) => notable.has(e.eventType) || e.subType === 'Shot' || e.subType === 'Corner')
    .slice(-6)
    .map((e) => e.summary)
    .filter(Boolean);

  return {
    homeGoals,
    awayGoals,
    scoreline: `${home} ${homeGoals}-${awayGoals} ${away}`,
    minute,
    recentNarrative,
  };
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
      usedTemplateCounts: (item.usedTemplateCounts && typeof item.usedTemplateCounts === 'object') ? item.usedTemplateCounts : {},
      recentTemplateIds: Array.isArray(item.recentTemplateIds) ? item.recentTemplateIds : [],
      recentDimensions: Array.isArray(item.recentDimensions) ? item.recentDimensions : [],
      templateLastSubject: (item.templateLastSubject && typeof item.templateLastSubject === 'object') ? item.templateLastSubject : {},
    };
  } catch {
    return { kickoffFired: false, aiTurn: false, kickoffQueue: [], usedTemplateCounts: {}, recentTemplateIds: [], recentDimensions: [], templateLastSubject: {} };
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

/** True if a question already exists for this (matchId, templateId, triggerEventId). */
async function questionExistsFor(matchId, templateId, triggerEventId) {
  try {
    const result = await ddb.send(new QueryCommand({
      TableName: QUESTIONS_TABLE,
      KeyConditionExpression: 'matchId = :m',
      FilterExpression: 'templateId = :t AND triggerEventId = :e',
      ExpressionAttributeValues: { ':m': matchId, ':t': templateId, ':e': triggerEventId },
      Select: 'COUNT',
    }));
    return (result.Count || 0) > 0;
  } catch (err) {
    console.error('questionExistsFor error:', err.message);
    return false; // fail open — better a rare dup than blocking all questions
  }
}

/** Return all questions asked so far for a match (lightweight projection). */
async function getAskedQuestions(matchId) {
  try {
    const result = await ddb.send(new QueryCommand({
      TableName: QUESTIONS_TABLE,
      KeyConditionExpression: 'matchId = :m',
      ProjectionExpression: '#q, category, options',
      ExpressionAttributeNames: { '#q': 'question' },
      ExpressionAttributeValues: { ':m': matchId },
    }));
    return result.Items || [];
  } catch (err) {
    console.error('getAskedQuestions error:', err.message);
    return [];
  }
}

/** Normalise a question into a token set for similarity comparison. */
function tokenSet(text) {
  return new Set(
    String(text || '')
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w.length > 2)
  );
}

/** Jaccard similarity over token sets. */
function jaccard(a, b) {
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const t of a) if (b.has(t)) inter++;
  return inter / (a.size + b.size - inter);
}

/** True if `candidate` is too similar (≥ 0.6 Jaccard) to any already-asked question. */
function isTooSimilar(candidate, askedTexts = []) {
  const cset = tokenSet(candidate);
  return askedTexts.some((t) => jaccard(cset, tokenSet(t)) >= 0.6);
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

async function callBedrock(trigger, dflEvent, recentEvents, matchInfo, playerLookup, teamLookup, live = {}, diversity = {}) {
  const match = matchInfo || {};
  const playerName = dflEvent.playerName || resolvePlayer(dflEvent.playerId, playerLookup);
  const teamName = dflEvent.teamName || resolveTeam(dflEvent.teamId, teamLookup);

  const askedTexts = diversity.askedTexts || [];
  const preferredDimension = diversity.preferredDimension || null;

  const systemPrompt = `You are a live football prediction quiz generator for the Bundesliga.
You write ONE short, exciting, PREDICTIVE multiple-choice question about what will happen NEXT, anchored to the specific moment just described.

HARD RULES:
- The question must be about the FUTURE (next goal, next 10 minutes, rest of half, full time) — never about what already happened.
- Be SPECIFIC to this moment: name the actual player and/or team in the trigger, and reflect the CURRENT live score and minute. Avoid generic filler like "will it be exciting?".
- Options must be concrete and mutually exclusive, and one must be clearly verifiable from match events (goals, cards, subs, shots, corners, offsides).
- 2-4 options. Vary the question shape across calls (over/under counts, who-next, yes/no on a specific player, which-team).
- Never reveal or assume the final result. Use ONLY the live score given.
- Keep the question under 120 characters.
- Return ONLY valid JSON, no markdown, no commentary.
${preferredDimension ? `- Focus this question on the "${preferredDimension}" dimension of play (it has been underused).` : ''}
${askedTexts.length ? `- Do NOT ask anything equivalent to these already-asked questions; pick a genuinely different angle:\n${askedTexts.map((t) => `  • ${t}`).join('\n')}` : ''}

Required JSON format:
{
  "question": "string",
  "options": ["string", ...],
  "category": "string (goal|cards|shots|subs|momentum|player)",
  "difficulty": "easy|medium|hard",
  "timeLimit": number,
  "resolutionType": "immediate|deferred|endOfMatch",
  "resolutionCriteria": "string: exactly how to determine the correct option from match events"
}`;

  const userMessage = JSON.stringify({
    match: {
      competition: match.competitionName || 'Bundesliga',
      homeTeam: match.homeTeamName || 'Home',
      awayTeam: match.guestTeamName || 'Away',
      liveScore: live.scoreline || match.liveScore || '0-0',
      minute: live.minute ?? (dflEvent.gameTime || '?'),
      stadium: match.stadiumName || '',
    },
    triggerMoment: {
      type: trigger.type,
      team: teamName,
      player: playerName,
      details: dflEvent.summary || '',
    },
    recentNarrative: (live.recentNarrative && live.recentNarrative.length)
      ? live.recentNarrative
      : recentEvents.slice(-8).map((e) => e.summary).filter(Boolean),
  });

  const response = await bedrock.send(new ConverseCommand({
    modelId: MODEL_ID,
    // Higher temperature for variety so questions feel fresh, not templated.
    inferenceConfig: { maxTokens: 512, temperature: 0.9, topP: 0.9 },
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
    // fallbackToFirst guarantees a resolvable option (never an unmatchable answer
    // that would score 0 for everyone).
    return parsed.map((r) => {
      const q = pendingQuestions.find((q) => q.questionId === r.questionId);
      const snapped = q ? snapToOption(r.correctAnswer, q.options, { fallbackToFirst: true }) : r.correctAnswer;
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
 * contains-match. With { fallbackToFirst: true } it returns the first option
 * rather than null, guaranteeing a ranked question always resolves to a real
 * option (so it can never score 0 for everyone due to an unmatchable answer).
 */
function snapToOption(answer, options = [], opts = {}) {
  if (options.length === 0) return answer ?? null;
  if (!answer) return opts.fallbackToFirst ? options[0] : null;
  const norm = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
  const a = norm(answer);
  // Exact normalised match.
  const exact = options.find((o) => norm(o) === a);
  if (exact) return exact;
  // Containment either direction (e.g. "Bayern" vs "Bayern Munich").
  const partial = options.find((o) => norm(o).includes(a) || a.includes(norm(o)));
  if (partial) return partial;
  return opts.fallbackToFirst ? options[0] : null;
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
