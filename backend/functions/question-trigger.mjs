import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand, PutCommand, GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);

const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;
const MATCH_STATE_TABLE = process.env.MATCH_STATE_TABLE;
const WS_ENDPOINT = process.env.WS_ENDPOINT;
const BEDROCK_ENDPOINT = process.env.BEDROCK_ENDPOINT; // To be provided later

/**
 * Question Trigger Lambda
 * 
 * Receives DFL events, buffers them, detects trigger conditions,
 * waits the appropriate delay, then generates and broadcasts questions.
 * 
 * Invoked by the Stream Lambda for each event, or via SQS/SNS.
 * 
 * Event payload:
 * {
 *   "matchId": "DFL-MAT-111111",
 *   "roomCode": "A7X9K2",
 *   "event": { ... parsed DFL event ... },
 *   "matchInfo": { ... match metadata ... },
 *   "playerLookup": { ... player name map ... },
 *   "teamLookup": { ... team name map ... }
 * }
 */
export const handler = async (event) => {
  try {
    const { matchId, roomCode, event: dflEvent, matchInfo, playerLookup, teamLookup } = event;

    if (!matchId || !dflEvent) {
      return { statusCode: 400, body: 'matchId and event required' };
    }

    // 1. Buffer the event in match state
    await bufferEvent(matchId, dflEvent);

    // 2. Check if this event is a trigger
    const trigger = detectTrigger(dflEvent);
    if (!trigger) {
      return { statusCode: 200, body: JSON.stringify({ triggered: false }) };
    }

    console.log(`Trigger detected: ${trigger.type} (delay: ${trigger.delayMs}ms)`);

    // 3. Wait the defined delay
    await sleep(trigger.delayMs);

    // 4. Get buffered context
    const context = await getMatchContext(matchId);

    // 5. Build Bedrock prompt
    const prompt = buildPrompt(trigger, dflEvent, context, matchInfo, playerLookup, teamLookup);

    // 6. Call Bedrock (placeholder — returns mock question until endpoint is configured)
    const question = await callBedrock(prompt);

    // 7. Broadcast question to players via WebSocket
    const targetRoom = roomCode || `match_${matchId}`;
    await broadcastQuestion(targetRoom, question, trigger);

    return {
      statusCode: 200,
      body: JSON.stringify({ triggered: true, triggerType: trigger.type, question }),
    };
  } catch (err) {
    console.error('Question trigger error:', err);
    return { statusCode: 500, body: err.message };
  }
};

// ─── Trigger Detection ──────────────────────────────────────────

/**
 * Fixed trigger events with defined delays.
 * Returns null if event is not a trigger.
 */
function detectTrigger(event) {
  const type = event.eventType;
  const subType = event.subType;

  // Goal
  if (type === 'Goal') {
    return { type: 'Goal', delayMs: randomBetween(30000, 45000) };
  }

  // Card (Yellow or Red)
  if (type === 'Card') {
    return { type: 'Card', delayMs: randomBetween(10000, 15000) };
  }

  // Substitution
  if (type === 'Substitution') {
    return { type: 'Substitution', delayMs: randomBetween(5000, 10000) };
  }

  // Corner kick
  if (subType === 'Corner' || event.isCorner === true || event.isCorner === 'true') {
    return { type: 'Corner', delayMs: 0 };
  }

  // Shot on target (saved, not a goal)
  if (subType === 'Shot' && event.evaluation && event.evaluation !== 'goal' && event.evaluation !== 'unsuccessful') {
    return { type: 'ShotSaved', delayMs: randomBetween(10000, 15000) };
  }

  // Free kick in dangerous area (x > 70m on a 105m pitch)
  if ((subType === 'Freekick' || event.isFreeKick === true || event.isFreeKick === 'true') && event.xPosition > 73.5) {
    return { type: 'FreeKick', delayMs: 0 };
  }

  // Halftime detection (game section change)
  if (event.gameSection === 'secondHalf' && event.eventType === 'KickOff') {
    return { type: 'Halftime', delayMs: randomBetween(15000, 20000) };
  }

  return null;
}

// ─── Event Buffering ────────────────────────────────────────────

async function bufferEvent(matchId, event) {
  // Store in DynamoDB match state (keep last 20 events)
  try {
    const stateKey = { matchId };
    const existing = await ddb.send(new GetCommand({
      TableName: MATCH_STATE_TABLE,
      Key: stateKey,
    }));

    let events = existing.Item?.recentEvents || [];
    events.push({
      eventId: event.eventId,
      eventType: event.eventType,
      subType: event.subType,
      team: event.teamName || event.teamId,
      player: event.playerName || event.playerId,
      evaluation: event.evaluation,
      minute: event.gameTime || event.eventTime,
      xPosition: event.xPosition,
      summary: event.summary,
    });

    // Keep only last 20
    if (events.length > 20) {
      events = events.slice(-20);
    }

    await ddb.send(new PutCommand({
      TableName: MATCH_STATE_TABLE,
      Item: {
        matchId,
        recentEvents: events,
        lastUpdated: new Date().toISOString(),
        ttl: Math.floor(Date.now() / 1000) + 7200, // 2 hour TTL
      },
    }));
  } catch (err) {
    console.error('Buffer event error:', err);
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
    console.error('Get context error:', err);
    return [];
  }
}

// ─── Prompt Building ────────────────────────────────────────────

function buildPrompt(trigger, dflEvent, recentEvents, matchInfo, playerLookup, teamLookup) {
  const match = matchInfo || {};
  const playerName = dflEvent.playerName || resolvePlayer(dflEvent.playerId, playerLookup);
  const teamName = dflEvent.teamName || resolveTeam(dflEvent.teamId, teamLookup);

  return {
    system: `You are a live football prediction quiz generator for the Bundesliga.
Generate engaging multiple-choice questions based on real-time match events.
Questions must be PREDICTIVE (what happens NEXT), not about what already happened.
Questions should be answerable within 15 seconds.
Return ONLY valid JSON with these fields: question, options (array of 4 strings), category, difficulty, timeLimit.`,

    userMessage: JSON.stringify({
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
      instruction: `A ${trigger.type} just occurred. Generate a prediction question about what happens next in this match.`,
    }),
  };
}

function resolvePlayer(playerId, lookup) {
  if (!playerId || !lookup || !lookup[playerId]) return playerId || 'Unknown';
  return lookup[playerId].shortName || `${lookup[playerId].firstName} ${lookup[playerId].lastName}`;
}

function resolveTeam(teamId, lookup) {
  if (!teamId || !lookup || !lookup[teamId]) return teamId || 'Unknown';
  return lookup[teamId].shortName || lookup[teamId].teamName;
}

// ─── Bedrock Integration ────────────────────────────────────────

async function callBedrock(prompt) {
  // Call the AI model endpoint
  if (BEDROCK_ENDPOINT) {
    try {
      const response = await fetch(BEDROCK_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system: prompt.system,
          messages: [{ role: 'user', content: prompt.userMessage }],
        }),
      });

      if (response.ok) {
        const result = await response.json();
        // Try to parse the response — it might be the question directly or wrapped
        if (result.question && result.options) {
          return result;
        }
        // If the model returns a content field with JSON string
        if (result.content) {
          try {
            return JSON.parse(result.content);
          } catch (_) {}
        }
        // If wrapped in a body field
        if (result.body) {
          try {
            const parsed = typeof result.body === 'string' ? JSON.parse(result.body) : result.body;
            if (parsed.question) return parsed;
          } catch (_) {}
        }
        console.log('Bedrock response (unparsed):', JSON.stringify(result));
        return result;
      } else {
        console.error('Bedrock API error:', response.status, await response.text());
      }
    } catch (err) {
      console.error('Bedrock call failed:', err.message);
    }
  }

  // Fallback to mock if endpoint not configured or call fails
  console.log('Using mock question (Bedrock unavailable)');
  const triggerData = JSON.parse(prompt.userMessage);
  const triggerType = triggerData.trigger.type;
  const player = triggerData.trigger.player || 'a player';

  const mockQuestions = {
    Goal: {
      question: `${player} just scored! What happens in the next 5 minutes?`,
      options: ['Another goal is scored', 'A card is given', 'A substitution is made', 'Nothing major happens'],
      category: 'match_prediction',
      difficulty: 'medium',
      timeLimit: 15,
    },
    Card: {
      question: `A card was just shown. Will there be another card this half?`,
      options: ['Yes, same team', 'Yes, other team', 'No more cards this half', 'A red card is coming'],
      category: 'discipline_prediction',
      difficulty: 'medium',
      timeLimit: 15,
    },
    Substitution: {
      question: `A substitution was just made. Will the substitute impact the game?`,
      options: ['Scores a goal', 'Gets an assist', 'Gets a card', 'No direct impact'],
      category: 'player_prediction',
      difficulty: 'hard',
      timeLimit: 15,
    },
    Corner: {
      question: `Corner kick coming up! What will happen?`,
      options: ['Goal scored', 'Shot on target', 'Cleared by defense', 'Foul committed'],
      category: 'set_piece_prediction',
      difficulty: 'easy',
      timeLimit: 15,
    },
    ShotSaved: {
      question: `Great save! What happens next?`,
      options: ['Corner kick', 'Goal kick', 'Another shot within 30s', 'Possession changes'],
      category: 'play_prediction',
      difficulty: 'easy',
      timeLimit: 15,
    },
    FreeKick: {
      question: `Free kick in a dangerous position! What's the outcome?`,
      options: ['Direct goal', 'Shot on target (saved)', 'Shot off target', 'Passed short'],
      category: 'set_piece_prediction',
      difficulty: 'medium',
      timeLimit: 15,
    },
    Halftime: {
      question: `Halftime! What will the final score be?`,
      options: ['Same as now', 'One more goal (either team)', 'Two+ more goals', 'A comeback happens'],
      category: 'match_prediction',
      difficulty: 'hard',
      timeLimit: 15,
    },
  };

  return mockQuestions[triggerType] || mockQuestions['Goal'];
}

// ─── WebSocket Broadcast ────────────────────────────────────────

async function broadcastQuestion(roomCode, question, trigger) {
  const connections = await getConnections(roomCode);
  if (connections.length === 0) {
    console.log(`No connections for room ${roomCode}`);
    return;
  }

  const message = {
    action: 'prediction_question',
    data: {
      question: question.question,
      options: question.options,
      category: question.category,
      difficulty: question.difficulty,
      timeLimit: question.timeLimit || 15,
      triggerType: trigger.type,
      timestamp: new Date().toISOString(),
    },
  };

  await broadcastToConnections(connections, message);
  console.log(`Question broadcast to ${connections.length} connections in ${roomCode}`);
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

function randomBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function sleep(ms) {
  if (ms <= 0) return Promise.resolve();
  return new Promise(resolve => setTimeout(resolve, ms));
}
