import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand, PutCommand, GetCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { BedrockRuntimeClient, ConverseCommand } from '@aws-sdk/client-bedrock-runtime';

const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);
const bedrock = new BedrockRuntimeClient({ region: 'us-east-1' });

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
// Maximum questions per match to control costs
const MAX_QUESTIONS_PER_MATCH = 20;
// Minimum seconds between questions to avoid flooding
const MIN_QUESTION_SPACING_MS = 60000; // 1 minute

export const handler = async (event) => {
  try {
    // Route to resolution handler if flagged
    if (event.resolve) {
      return resolveQuestions(event);
    }

    const { matchId, roomCode, event: dflEvent, matchInfo, playerLookup, teamLookup } = event;

    if (!matchId || !dflEvent) {
      return { statusCode: 400, body: 'matchId and event required' };
    }

    // 1. Buffer the event (always, for context)
    await bufferEvent(matchId, dflEvent);

    // 2. Check if this event is a trigger
    const trigger = detectTrigger(dflEvent);
    if (!trigger) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'not a trigger event' }) };
    }

    console.log(`Trigger detected: ${trigger.type} for event ${dflEvent.eventType}/${dflEvent.subType || ''}`);

    // 3. Check max questions cap
    let existingQuestions = 0;
    try {
      existingQuestions = await getQuestionCount(matchId);
      console.log(`Question count for ${matchId}: ${existingQuestions}`);
    } catch (e) {
      console.error('Failed to get question count:', e.message);
    }
    if (existingQuestions >= MAX_QUESTIONS_PER_MATCH) {
      console.log(`Max questions reached (${existingQuestions}/${MAX_QUESTIONS_PER_MATCH}), skipping`);
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'max questions reached' }) };
    }

    // 4. Check minimum spacing between questions
    let lastQuestionTime = null;
    try {
      lastQuestionTime = await getLastQuestionTime(matchId);
      console.log(`Last question time: ${lastQuestionTime ? new Date(lastQuestionTime).toISOString() : 'none'}`);
    } catch (e) {
      console.error('Failed to get last question time:', e.message);
    }
    if (lastQuestionTime && (Date.now() - lastQuestionTime) < MIN_QUESTION_SPACING_MS) {
      console.log(`Too soon since last question (${Math.round((Date.now() - lastQuestionTime) / 1000)}s ago), skipping`);
      return { statusCode: 200, body: JSON.stringify({ triggered: false, reason: 'too soon' }) };
    }

    // 5. Wait the trigger delay (skip delay for faster testing — set to 0)
    const actualDelay = Math.min(trigger.delayMs, 5000); // Cap at 5s for testing
    if (actualDelay > 0) {
      console.log(`Waiting ${actualDelay}ms before generating question...`);
      await sleep(actualDelay);
    }

    // 6. Get match context and call Bedrock
    console.log('Calling Bedrock to generate question...');
    const context = await getMatchContext(matchId);
    const question = await callBedrock(trigger, dflEvent, context, matchInfo, playerLookup, teamLookup);

    if (!question || !question.question || !question.options) {
      console.error('Bedrock returned invalid question:', JSON.stringify(question));
      return { statusCode: 200, body: JSON.stringify({ triggered: true, error: 'Invalid question from Bedrock' }) };
    }
    console.log(`Question generated: "${question.question}" with ${question.options.length} options`);

    // 7. Store question in DynamoDB
    const questionId = `q_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    await ddb.send(new PutCommand({
      TableName: QUESTIONS_TABLE,
      Item: {
        matchId,
        questionId,
        question: question.question,
        options: question.options,
        category: question.category || 'general',
        difficulty: question.difficulty || 'medium',
        timeLimit: question.timeLimit || 15,
        resolutionType: question.resolutionType || 'deferred',
        resolutionCriteria: question.resolutionCriteria || '',
        correctAnswer: null,
        status: 'pending',
        triggerType: trigger.type,
        triggerEvent: dflEvent.summary || '',
        userPicks: {},
        createdAt: new Date().toISOString(),
        ttl: Math.floor(Date.now() / 1000) + 86400,
      },
    }));

    // 8. Broadcast question to players
    const targetRoom = roomCode || `match_${matchId}`;
    await broadcastQuestion(targetRoom, question, questionId, trigger);

    return {
      statusCode: 200,
      body: JSON.stringify({ triggered: true, questionId, triggerType: trigger.type }),
    };
  } catch (err) {
    console.error('Question trigger error:', err);
    return { statusCode: 500, body: err.message };
  }
};

/**
 * End-of-match resolution handler.
 * Call this when the final whistle event is detected.
 *
 * Event payload:
 * { "matchId": "...", "roomCode": "...", "matchSummary": { ... } }
 */
export const resolveQuestions = async (event) => {
  try {
    const { matchId, roomCode, matchSummary } = event;

    if (!matchId) {
      return { statusCode: 400, body: 'matchId required' };
    }

    // 1. Get all pending questions for this match
    const result = await ddb.send(new QueryCommand({
      TableName: QUESTIONS_TABLE,
      KeyConditionExpression: 'matchId = :matchId',
      FilterExpression: '#s = :pending',
      ExpressionAttributeNames: { '#s': 'status' },
      ExpressionAttributeValues: { ':matchId': matchId, ':pending': 'pending' },
    }));

    const pendingQuestions = result.Items || [];
    if (pendingQuestions.length === 0) {
      return { statusCode: 200, body: JSON.stringify({ resolved: 0 }) };
    }

    console.log(`Resolving ${pendingQuestions.length} pending questions for match ${matchId}`);

    // 2. Get full match event log
    const matchContext = await getMatchContext(matchId);

    // 3. Call Bedrock to resolve all questions
    const resolutions = await resolveWithBedrock(pendingQuestions, matchContext, matchSummary);

    // 4. Update each question with correct answer
    for (const resolution of resolutions) {
      await ddb.send(new PutCommand({
        TableName: QUESTIONS_TABLE,
        Item: {
          ...pendingQuestions.find(q => q.questionId === resolution.questionId),
          correctAnswer: resolution.correctAnswer,
          status: 'resolved',
          resolvedAt: new Date().toISOString(),
        },
      }));
    }

    // 5. Broadcast results to players
    const targetRoom = roomCode || `match_${matchId}`;
    await broadcastResolutions(targetRoom, resolutions, pendingQuestions);

    return {
      statusCode: 200,
      body: JSON.stringify({ resolved: resolutions.length }),
    };
  } catch (err) {
    console.error('Resolution error:', err);
    return { statusCode: 500, body: err.message };
  }
};

// ─── Trigger Detection ──────────────────────────────────────────

function detectTrigger(event) {
  const type = event.eventType;
  const subType = event.subType;

  // Goal scored (SuccessfulShot in the XML)
  if (type === 'Goal') return { type: 'Goal', delayMs: randomBetween(30000, 45000) };

  // Yellow/Red card
  if (type === 'Card') return { type: 'Card', delayMs: randomBetween(10000, 15000) };

  // Substitution
  if (type === 'Substitution') return { type: 'Substitution', delayMs: randomBetween(5000, 10000) };

  // Corner kick
  if (subType === 'Corner') return { type: 'Corner', delayMs: 0 };

  // Shot saved by goalkeeper (not a goal, not blocked by outfield player)
  if (subType === 'Shot' && event.evaluation && event.evaluation !== 'goal' && event.evaluation !== 'unsuccessful' && event.evaluation !== 'blocked') {
    return { type: 'ShotSaved', delayMs: randomBetween(10000, 15000) };
  }

  // Free kick in dangerous area (x < 30 means close to opponent goal in this coordinate system)
  if (subType === 'Freekick' && event.xPosition < 30) {
    return { type: 'FreeKick', delayMs: 0 };
  }

  // Penalty
  if (type === 'Penalty') return { type: 'Penalty', delayMs: 0 };

  // KickOff for second half = halftime just ended
  if (event.gameSection === 'secondHalf' && type === 'KickOff') {
    return { type: 'Halftime', delayMs: randomBetween(15000, 20000) };
  }

  // First KickOff = match start
  if (type === 'KickOff') return { type: 'KickOff', delayMs: 5000 };

  return null;
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
    return JSON.parse(jsonMatch[0]);
  } catch (e) {
    console.error('Resolution JSON parse error:', e);
    return [];
  }
}

// ─── Event Buffering ────────────────────────────────────────────

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
      team: event.teamName || event.teamId || null,
      player: event.playerName || event.playerId || null,
      evaluation: event.evaluation || null,
      minute: event.gameTime || event.eventTime || null,
      xPosition: event.xPosition || 0,
      summary: event.summary || '',
    });

    if (events.length > 50) events = events.slice(-50);

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

async function broadcastResolutions(roomCode, resolutions, questions) {
  const connections = await getConnections(roomCode);
  if (connections.length === 0) return;

  const results = resolutions.map(r => {
    const q = questions.find(q => q.questionId === r.questionId);
    return {
      questionId: r.questionId,
      question: q?.question || '',
      correctAnswer: r.correctAnswer,
      userPicks: q?.userPicks || {},
    };
  });

  const message = {
    action: 'questions_resolved',
    data: { results },
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
