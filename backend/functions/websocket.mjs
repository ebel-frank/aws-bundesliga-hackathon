import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, DeleteCommand, ScanCommand, GetCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const lambdaClient = new LambdaClient({});
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;
const QUESTIONS_TABLE = process.env.QUESTIONS_TABLE;
const CATCHUP_GRACE_SECONDS = 20; // late answers accepted this long after the timer

// ─── Auto match orchestration (game_started → stream DFL data) ───
const DFL_EVENTS_FUNCTION = process.env.DFL_EVENTS_FUNCTION;
const QUESTION_TRIGGER_FUNCTION = process.env.QUESTION_TRIGGER_FUNCTION;
const DFL_DATA_BUCKET = process.env.DFL_DATA_BUCKET;
// The single real anonymised fixture's S3 keys. Every match card streams this
// data (it's the only real match in the bucket), tagged with the room's matchId.
const DFL_EVENTS_KEY = process.env.DFL_EVENTS_KEY;
const DFL_MATCH_INFO_KEY = process.env.DFL_MATCH_INFO_KEY;
const STREAM_DELAY_MS = process.env.STREAM_DELAY_MS ? parseInt(process.env.STREAM_DELAY_MS, 10) : 3000;
// In-room rooms have a code; the streamer broadcasts to that room.
// Track which rooms have already been started so a late game_started broadcast
// (or a second host click) doesn't kick off a duplicate stream.
const startedRooms = new Set();

/**
 * When the host starts the game, automatically: reset prior match state, then
 * invoke the DFL streamer (which waits a lead-in, fires the kick-off questions,
 * and streams the real match events). No manual trigger script needed.
 */
async function orchestrateMatchStart(roomCode, data = {}) {
  if (!DFL_EVENTS_FUNCTION) {
    console.warn('DFL_EVENTS_FUNCTION not configured — skipping auto-stream');
    return;
  }
  const matchId = data.matchId;
  if (!roomCode || !matchId) {
    console.warn('orchestrateMatchStart missing roomCode/matchId — skipping');
    return;
  }
  const key = `${roomCode}:${matchId}`;
  if (startedRooms.has(key)) {
    console.log(`Match already started for ${key} — ignoring duplicate game_started`);
    return;
  }
  startedRooms.add(key);

  // 1. Reset prior questions/state so the match can be demoed repeatedly.
  if (QUESTION_TRIGGER_FUNCTION) {
    try {
      await lambdaClient.send(new InvokeCommand({
        FunctionName: QUESTION_TRIGGER_FUNCTION,
        InvocationType: 'RequestResponse',
        Payload: Buffer.from(JSON.stringify({ reset: true, matchId })),
      }));
    } catch (err) {
      console.error('Match reset failed (continuing):', err.message);
    }
  }

  // 2. Kick off the streamer asynchronously (it runs for the whole match).
  try {
    await lambdaClient.send(new InvokeCommand({
      FunctionName: DFL_EVENTS_FUNCTION,
      InvocationType: 'Event', // fire-and-forget; streams over many minutes
      Payload: Buffer.from(JSON.stringify({
        bucket: DFL_DATA_BUCKET,
        eventsKey: DFL_EVENTS_KEY,
        matchInfoKey: DFL_MATCH_INFO_KEY,
        matchId,
        roomCode,
        delayMs: STREAM_DELAY_MS,
        startDelayMs: 5000, // 5s lead-in before the first (kick-off) event
      })),
    }));
    console.log(`Auto-stream invoked for room ${roomCode}, match ${matchId}`);
  } catch (err) {
    console.error('orchestrateMatchStart invoke failed:', err.message);
    startedRooms.delete(key); // allow a retry
  }
}

/**
 * Persist a player's prediction pick into the question's userPicks map so the
 * QuestionTrigger/Resolver functions can score it server-side. Records
 * answeredAt (server-authoritative speed), late (catch-up answers), and
 * changeCount (kick-off answer changes).
 */
async function persistPick(data = {}) {
  const { matchId, questionId, userId, pick } = data;
  if (!matchId || !questionId || !userId || pick == null) return;
  try {
    const res = await ddb.send(new GetCommand({ TableName: QUESTIONS_TABLE, Key: { matchId, questionId } }));
    const q = res.Item;
    if (!q || q.status === 'resolved') return; // can't answer a resolved question

    const now = Date.now();
    const createdMs = q.createdAt ? new Date(q.createdAt).getTime() : now;
    const timeLimitMs = (q.timeLimit || 15) * 1000;
    const isKickoff = q.category === 'kickoff';
    const elapsedMs = now - createdMs;

    // Catch-up rule: realtime questions accept late answers only within the grace
    // window (scored at the flat minimum later). Kick-off questions stay open all match.
    const late = elapsedMs > timeLimitMs;
    if (!isKickoff && late && elapsedMs > timeLimitMs + CATCHUP_GRACE_SECONDS * 1000) {
      return; // too late even for catch-up
    }

    const picks = q.userPicks || {};
    const existing = picks[userId];
    const prevChange = (typeof existing === 'object' && existing.changeCount) || 0;
    const existingPick = existing == null ? null : (typeof existing === 'string' ? existing : existing.pick);
    const isChange = existingPick != null && existingPick !== pick;

    picks[userId] = {
      pick,
      answeredAt: new Date(now).toISOString(),
      late,
      changeCount: prevChange + (isChange ? 1 : 0),
    };

    await ddb.send(new PutCommand({ TableName: QUESTIONS_TABLE, Item: { ...q, userPicks: picks } }));
  } catch (err) {
    console.error('persistPick error:', err.message);
  }
}

export const connect = async (event) => {
  const connectionId = event.requestContext.connectionId;
  const roomCode = event.queryStringParameters?.roomCode || '';
  const userId = event.queryStringParameters?.userId || '';

  const ttl = Math.floor(Date.now() / 1000) + 3600; // 1 hour TTL

  await ddb.send(new PutCommand({
    TableName: CONNECTIONS_TABLE,
    Item: { connectionId, roomCode, userId, ttl },
  }));

  return { statusCode: 200, body: 'Connected' };
};

export const disconnect = async (event) => {
  const connectionId = event.requestContext.connectionId;

  await ddb.send(new DeleteCommand({
    TableName: CONNECTIONS_TABLE,
    Key: { connectionId },
  }));

  return { statusCode: 200, body: 'Disconnected' };
};

export const message = async (event) => {
  const connectionId = event.requestContext.connectionId;
  const body = JSON.parse(event.body || '{}');
  const { action, roomCode, data } = body;

  // Persist prediction picks so the server can score them authoritatively.
  if (action === 'submit_pick') {
    await persistPick(data);
  }

  // Host started the game → auto-reset + auto-stream the real match data.
  if (action === 'game_started') {
    await orchestrateMatchStart(roomCode, data);
  }

  // Get all connections in the same room
  const result = await ddb.send(new ScanCommand({
    TableName: CONNECTIONS_TABLE,
    FilterExpression: 'roomCode = :roomCode',
    ExpressionAttributeValues: { ':roomCode': roomCode },
  }));

  const connections = result.Items || [];
  const domain = event.requestContext.domainName;
  const stage = event.requestContext.stage;
  const apiClient = new ApiGatewayManagementApiClient({
    endpoint: `https://${domain}/${stage}`,
  });

  // Broadcast to all connections in the room (except sender for some actions)
  const message = JSON.stringify({ action, data, senderId: connectionId });

  const sendPromises = connections.map(async (conn) => {
    if (conn.connectionId === connectionId && action !== 'game_started') return;
    try {
      await apiClient.send(new PostToConnectionCommand({
        ConnectionId: conn.connectionId,
        Data: Buffer.from(message),
      }));
    } catch (err) {
      if (err.statusCode === 410) {
        // Stale connection — remove it
        await ddb.send(new DeleteCommand({
          TableName: CONNECTIONS_TABLE,
          Key: { connectionId: conn.connectionId },
        }));
      }
    }
  });

  await Promise.all(sendPromises);

  return { statusCode: 200, body: 'Message sent' };
};
