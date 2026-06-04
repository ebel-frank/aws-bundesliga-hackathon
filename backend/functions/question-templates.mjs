/**
 * Question Template Registry
 *
 * The deterministic backbone of the prediction engine. Each template owns:
 *   - a trigger predicate (which DFL event fires it)
 *   - a builder (produces the question text + options + resolver metadata)
 *   - a resolver (decides the correct answer from the event log — pure code)
 *
 * Resolvers NEVER use an LLM, so ranked scoring is always fair and deterministic.
 * AI is layered on top of these (phrasing enrichment) and alongside them
 * (separate AI-generated "color" questions) in question-trigger.mjs.
 *
 * resolutionType:
 *   - 'immediate'  : answer known the moment the trigger fires (knownAnswer set).
 *   - 'deferred'   : resolved by a bounded window of following events.
 *   - 'endOfMatch' : resolved from the full event log at the final whistle.
 *
 * scoring:
 *   - 'ranked' : affects the leaderboard (deterministic resolution only).
 *   - 'bonus'  : non-ranking flavour (used for proxies / AI questions).
 */

// ─── Helpers ────────────────────────────────────────────────────

function goalEvents(events) {
  return events.filter((e) => e.eventType === 'Goal');
}

function countGoals(events) {
  return goalEvents(events).length;
}

function goalsForTeam(events, teamId) {
  return goalEvents(events).filter((e) => e.teamId === teamId).length;
}

function countSubType(events, subType) {
  return events.filter((e) => e.subType === subType).length;
}

function firstKickoffTime(events) {
  const ko = events.find((e) => e.eventType === 'KickOff');
  return ko ? new Date(ko.eventTime).getTime() : null;
}

/** Minute of an event relative to the first kick-off (null if not computable). */
function minuteOf(events, ev) {
  const start = firstKickoffTime(events);
  if (!start || !ev.eventTime) return null;
  return (new Date(ev.eventTime).getTime() - start) / 60000;
}

/** Events that occur strictly after the given eventId, in stream order. */
function eventsAfter(events, eventId) {
  const idx = events.findIndex((e) => e.eventId === eventId);
  return idx === -1 ? [] : events.slice(idx + 1);
}

// ─── Templates ──────────────────────────────────────────────────

export const TEMPLATES = [
  // ===== SECTION 1: KICK-OFF (fired once on first KickOff) =====
  {
    id: 'ko_final_result',
    section: 'kickoff',
    scoring: 'ranked',
    once: true,
    delayMs: 3000,
    trigger: (ev, state) => ev.eventType === 'KickOff' && !state.kickoffFired,
    build: (ev, ctx) => ({
      text: `Full-time result: ${ctx.homeTeamName} vs ${ctx.awayTeamName}?`,
      options: [`${ctx.homeTeamName} win`, 'Draw', `${ctx.awayTeamName} win`],
      timeLimit: 20,
      resolutionType: 'endOfMatch',
      resolverParams: {},
    }),
    resolve: (q, events, ctx) => {
      const h = goalsForTeam(events, ctx.homeTeamId);
      const a = goalsForTeam(events, ctx.awayTeamId);
      if (h > a) return `${ctx.homeTeamName} win`;
      if (a > h) return `${ctx.awayTeamName} win`;
      return 'Draw';
    },
  },
  {
    id: 'ko_over_under_25',
    section: 'kickoff',
    scoring: 'ranked',
    once: true,
    delayMs: 3000,
    trigger: (ev, state) => ev.eventType === 'KickOff' && !state.kickoffFired,
    build: (ev, ctx) => ({
      text: `${ctx.homeTeamName} vs ${ctx.awayTeamName}: over or under 2.5 total goals?`,
      options: ['Over 2.5', 'Under 2.5'],
      timeLimit: 20,
      resolutionType: 'endOfMatch',
      resolverParams: {},
    }),
    resolve: (q, events) => (countGoals(events) > 2 ? 'Over 2.5' : 'Under 2.5'),
  },
  {
    id: 'ko_corners_85',
    section: 'kickoff',
    scoring: 'ranked',
    once: true,
    delayMs: 3000,
    trigger: (ev, state) => ev.eventType === 'KickOff' && !state.kickoffFired,
    build: (ev, ctx) => ({
      text: `${ctx.homeTeamName} vs ${ctx.awayTeamName}: more than 8.5 total corners?`,
      options: ['Over 8.5', 'Under 8.5'],
      timeLimit: 20,
      resolutionType: 'endOfMatch',
      resolverParams: {},
    }),
    resolve: (q, events) => (countSubType(events, 'Corner') > 8 ? 'Over 8.5' : 'Under 8.5'),
  },
  {
    id: 'ko_first_scorer_team',
    section: 'kickoff',
    scoring: 'ranked',
    once: true,
    delayMs: 3000,
    trigger: (ev, state) => ev.eventType === 'KickOff' && !state.kickoffFired,
    build: (ev, ctx) => ({
      text: 'Which team scores first?',
      options: [ctx.homeTeamName, ctx.awayTeamName, 'No goals'],
      timeLimit: 20,
      resolutionType: 'endOfMatch',
      resolverParams: {},
    }),
    resolve: (q, events, ctx) => {
      const first = goalEvents(events)[0];
      if (!first) return 'No goals';
      return first.teamId === ctx.homeTeamId ? ctx.homeTeamName : ctx.awayTeamName;
    },
  },
  {
    id: 'ko_total_passes_800',
    section: 'kickoff',
    scoring: 'ranked',
    once: true,
    delayMs: 3000,
    trigger: (ev, state) => ev.eventType === 'KickOff' && !state.kickoffFired,
    build: (ev, ctx) => ({
      text: `${ctx.homeTeamName} vs ${ctx.awayTeamName}: will total passes exceed 800?`,
      options: ['Over 800', 'Under 800'],
      timeLimit: 20,
      resolutionType: 'endOfMatch',
      resolverParams: {},
    }),
    resolve: (q, events) => (countSubType(events, 'Pass') > 800 ? 'Over 800' : 'Under 800'),
  },
  {
    id: 'ko_goal_first_15',
    section: 'kickoff',
    scoring: 'ranked',
    once: true,
    delayMs: 3000,
    trigger: (ev, state) => ev.eventType === 'KickOff' && !state.kickoffFired,
    build: (ev, ctx) => ({
      text: `Fast start? A goal in the first 15 minutes of ${ctx.homeTeamName} vs ${ctx.awayTeamName}?`,
      options: ['Yes', 'No'],
      timeLimit: 20,
      resolutionType: 'endOfMatch',
      resolverParams: {},
    }),
    resolve: (q, events) => {
      const first = goalEvents(events)[0];
      if (!first) return 'No';
      const m = minuteOf(events, first);
      return m !== null && m <= 15 ? 'Yes' : 'No';
    },
  },
  {
    id: 'ko_possession_55',
    section: 'kickoff',
    scoring: 'bonus', // possession is a pass-share proxy, not official — non-ranking
    once: true,
    delayMs: 3000,
    trigger: (ev, state) => ev.eventType === 'KickOff' && !state.kickoffFired,
    build: (ev, ctx) => ({
      text: `Possession king: which side holds more of the ball?`,
      options: [ctx.homeTeamName, ctx.awayTeamName],
      timeLimit: 20,
      resolutionType: 'endOfMatch',
      resolverParams: {},
    }),
    resolve: (q, events, ctx) => {
      const home = events.filter((e) => e.subType === 'Pass' && e.teamId === ctx.homeTeamId).length;
      const away = events.filter((e) => e.subType === 'Pass' && e.teamId === ctx.awayTeamId).length;
      return home >= away ? ctx.homeTeamName : ctx.awayTeamName;
    },
  },

  // ===== SECTION 2: RULE-BASED REAL-TIME =====
  {
    // H. Goal trivia — answer is known the instant the goal fires.
    id: 'rt_goal_box_trivia',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 4000,
    trigger: (ev) => ev.eventType === 'Goal',
    build: (ev) => ({
      text: `GOAL${ev.playerName ? ` by ${ev.playerName}` : ''}! Was the shot from inside or outside the box?`,
      options: ['Inside the box', 'Outside the box'],
      timeLimit: 12,
      resolutionType: 'immediate',
      knownAnswer: ev.insideBox ? 'Inside the box' : 'Outside the box',
      resolverParams: {},
    }),
    resolve: (q) => q.knownAnswer,
  },
  {
    // A. Shot on target (saved/blocked, not a goal) → next shot a goal?
    id: 'rt_next_shot_goal',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 0,
    trigger: (ev) =>
      ev.subType === 'Shot' &&
      ev.eventType !== 'Goal' &&
      ['savedByGoalkeeper', 'blocked', 'wide'].includes(ev.evaluation),
    build: (ev) => ({
      text: 'That was close! Will the NEXT shot at goal be a goal?',
      options: ['Yes', 'No'],
      timeLimit: 10,
      resolutionType: 'deferred',
      windowSeconds: 600, // resolve on next shot, or at this window cap
      resolverParams: { afterEventId: ev.eventId },
    }),
    resolve: (q, events) => {
      const after = eventsAfter(events, q.resolverParams.afterEventId);
      const nextShot = after.find((e) => e.subType === 'Shot' || e.eventType === 'Goal');
      if (!nextShot) return null; // not enough info yet
      return nextShot.eventType === 'Goal' ? 'Yes' : 'No';
    },
  },
  {
    // B. Corner → shot at goal within 30s?
    id: 'rt_corner_to_shot',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 0,
    trigger: (ev) => ev.subType === 'Corner',
    build: (ev) => ({
      text: 'Set-piece alert! Will this corner lead to a shot at goal within 30s?',
      options: ['Yes', 'No'],
      timeLimit: 10,
      resolutionType: 'deferred',
      windowSeconds: 30,
      resolverParams: { afterEventId: ev.eventId, afterTime: ev.eventTime },
    }),
    resolve: (q, events) => {
      const after = eventsAfter(events, q.resolverParams.afterEventId);
      const start = new Date(q.resolverParams.afterTime).getTime();
      const within = after.filter(
        (e) => new Date(e.eventTime).getTime() - start <= 30000
      );
      const hitShot = within.some((e) => e.subType === 'Shot' || e.eventType === 'Goal');
      // If we've seen events past the 30s window and found no shot, it's No.
      const windowClosed = after.some(
        (e) => new Date(e.eventTime).getTime() - start > 30000
      );
      if (hitShot) return 'Yes';
      if (windowClosed) return 'No';
      return null;
    },
  },
  {
    // C. Yellow card → second booking / red for that player by full time?
    id: 'rt_card_second_booking',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 8000,
    trigger: (ev) => ev.eventType === 'Card' && ev.cardColor === 'yellow',
    build: (ev) => ({
      text: `${ev.playerName || 'That player'} is in the book. A second yellow or red before full time?`,
      options: ['Yes', 'No'],
      timeLimit: 12,
      resolutionType: 'endOfMatch',
      resolverParams: { playerId: ev.playerId },
    }),
    resolve: (q, events) => {
      const bookings = events.filter(
        (e) => e.eventType === 'Card' && e.playerId === q.resolverParams.playerId
      );
      const red = events.some(
        (e) => e.eventType === 'Card' && e.playerId === q.resolverParams.playerId && e.cardColor === 'red'
      );
      return bookings.length >= 2 || red ? 'Yes' : 'No';
    },
  },
  {
    // D. Substitution → does the sub record a goal/assist before full time?
    id: 'rt_sub_impact',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 5000,
    trigger: (ev) => ev.eventType === 'Substitution' && ev.playerInId,
    build: (ev) => ({
      text: `Impact sub? Will ${ev.playerInName || 'the new player'} get a goal or assist before full time?`,
      options: ['Yes', 'No'],
      timeLimit: 12,
      resolutionType: 'endOfMatch',
      resolverParams: { playerInId: ev.playerInId, afterEventId: ev.eventId },
    }),
    resolve: (q, events) => {
      const after = eventsAfter(events, q.resolverParams.afterEventId);
      const pid = q.resolverParams.playerInId;
      const scored = after.some((e) => e.eventType === 'Goal' && e.playerId === pid);
      const assisted = after.some((e) => e.eventType === 'Goal' && e.assistId === pid);
      return scored || assisted ? 'Yes' : 'No';
    },
  },
  {
    // E. Dangerous free kick (close to goal) → over the wall / on target?
    id: 'rt_freekick_on_target',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 0,
    // X-Position near the attacking goal line (pitch ~105m; <30 or >75 = dangerous third)
    trigger: (ev) =>
      ev.subType === 'Freekick' && (ev.xPosition > 75 || ev.xPosition < 30),
    build: (ev) => ({
      text: 'Free kick in a dangerous spot! Will it produce a shot at goal within 20s?',
      options: ['Yes', 'No'],
      timeLimit: 10,
      resolutionType: 'deferred',
      windowSeconds: 20,
      resolverParams: { afterEventId: ev.eventId, afterTime: ev.eventTime },
    }),
    resolve: (q, events) => {
      const after = eventsAfter(events, q.resolverParams.afterEventId);
      const start = new Date(q.resolverParams.afterTime).getTime();
      const within = after.filter((e) => new Date(e.eventTime).getTime() - start <= 20000);
      const hitShot = within.some((e) => e.subType === 'Shot' || e.eventType === 'Goal');
      const windowClosed = after.some((e) => new Date(e.eventTime).getTime() - start > 20000);
      if (hitShot) return 'Yes';
      if (windowClosed) return 'No';
      return null;
    },
  },
  {
    // F. Penalty → will the goalkeeper save it?
    id: 'rt_penalty_save',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 0,
    trigger: (ev) => ev.eventType === 'Penalty',
    build: (ev) => ({
      text: 'Pressure point — PENALTY! Will it be scored?',
      options: ['Scored', 'Missed / Saved'],
      timeLimit: 10,
      resolutionType: 'deferred',
      windowSeconds: 120,
      resolverParams: { afterEventId: ev.eventId },
    }),
    resolve: (q, events) => {
      const after = eventsAfter(events, q.resolverParams.afterEventId);
      // Look at the next shot-related event after the penalty award.
      const next = after.find(
        (e) => e.eventType === 'Goal' || e.subType === 'Shot'
      );
      if (!next) return null;
      return next.eventType === 'Goal' ? 'Scored' : 'Missed / Saved';
    },
  },
  {
    // G. Offside → will this team be caught offside again this half?
    id: 'rt_offside_repeat',
    section: 'realtime',
    scoring: 'ranked',
    delayMs: 4000,
    trigger: (ev) => ev.eventType === 'Offside',
    build: (ev) => ({
      text: `${ev.teamName || 'They'} caught offside. Another offside flag before half-time?`,
      options: ['Yes', 'No'],
      timeLimit: 12,
      resolutionType: 'endOfMatch',
      resolverParams: { teamId: ev.teamId, afterEventId: ev.eventId, gameSection: ev.gameSection },
    }),
    resolve: (q, events) => {
      const after = eventsAfter(events, q.resolverParams.afterEventId);
      const again = after.some(
        (e) => e.eventType === 'Offside' && e.teamId === q.resolverParams.teamId
      );
      return again ? 'Yes' : 'No';
    },
  },
];

// ─── Public API ─────────────────────────────────────────────────

/**
 * Returns the templates triggered by an event given current match state.
 * `state` carries flags like { kickoffFired: bool }.
 */
export function findTriggeredTemplates(event, state = {}) {
  return TEMPLATES.filter((t) => {
    try {
      return t.trigger(event, state);
    } catch {
      return false;
    }
  });
}

export function getTemplate(id) {
  return TEMPLATES.find((t) => t.id === id) || null;
}

/**
 * Resolve a stored question deterministically.
 * Returns the correct answer string, or null if not yet resolvable.
 */
export function resolveTemplate(question, events, ctx) {
  const t = getTemplate(question.templateId);
  if (!t || typeof t.resolve !== 'function') return null;
  try {
    return t.resolve(question, events, ctx);
  } catch (err) {
    console.error(`resolveTemplate error for ${question.templateId}:`, err.message);
    return null;
  }
}
