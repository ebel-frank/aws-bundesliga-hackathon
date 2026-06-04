import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, DeleteCommand, ScanCommand, GetCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;
const QUESTIONS_TABLE = process.env.QUESTIONS_TABLE;
const CATCHUP_GRACE_SECONDS = 20; // late answers accepted this long after the timer

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
