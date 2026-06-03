import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand, PutCommand, GetCommand, UpdateCommand, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const TABLE = process.env.ROOMS_TABLE;
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;

function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

async function broadcastToRoom(roomCode, message, wsEndpoint) {
  if (!wsEndpoint) return;

  const result = await ddb.send(new ScanCommand({
    TableName: CONNECTIONS_TABLE,
    FilterExpression: 'roomCode = :roomCode',
    ExpressionAttributeValues: { ':roomCode': roomCode },
  }));

  const connections = result.Items || [];
  if (connections.length === 0) return;

  const apiClient = new ApiGatewayManagementApiClient({ endpoint: wsEndpoint });
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

export const getRooms = async (event) => {
  try {
    const matchId = event.pathParameters?.matchId;
    if (!matchId) return { statusCode: 400, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'matchId required' }) };

    const result = await ddb.send(new QueryCommand({
      TableName: TABLE,
      IndexName: 'matchId-index',
      KeyConditionExpression: 'matchId = :matchId',
      ExpressionAttributeValues: { ':matchId': matchId },
    }));

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ rooms: result.Items || [] }),
    };
  } catch (err) {
    console.error('getRooms error:', err);
    return { statusCode: 500, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Failed to fetch rooms' }) };
  }
};

export const createRoom = async (event) => {
  try {
    const body = JSON.parse(event.body || '{}');
    const { matchId, roomName, maxPlayers = 6, isPrivate = false, hostUserId, hostDisplayName } = body;

    if (!matchId || !roomName || !hostUserId) {
      return { statusCode: 400, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'matchId, roomName, and hostUserId are required' }) };
    }

    const roomCode = generateCode();
    const room = {
      roomCode,
      matchId,
      roomName,
      maxPlayers,
      isPrivate,
      hostUserId,
      members: [{
        userId: hostUserId,
        displayName: hostDisplayName || 'Host',
        avatarColor: 0xFF2979FF,
        totalXP: 0,
        streak: 0,
        badges: [],
        isHost: true,
        isConnected: true,
      }],
      status: 'waiting',
      totalRounds: 5,
      createdAt: new Date().toISOString(),
    };

    await ddb.send(new PutCommand({ TableName: TABLE, Item: room }));

    return {
      statusCode: 201,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ room }),
    };
  } catch (err) {
    console.error('createRoom error:', err);
    return { statusCode: 500, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Failed to create room' }) };
  }
};

export const joinRoom = async (event) => {
  try {
    const roomCode = event.pathParameters?.roomCode;
    const body = JSON.parse(event.body || '{}');
    const { userId, displayName, code } = body;

    if (!roomCode || !userId) {
      return { statusCode: 400, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'roomCode and userId required' }) };
    }

    // Get the room
    const result = await ddb.send(new GetCommand({ TableName: TABLE, Key: { roomCode } }));
    const room = result.Item;

    if (!room) {
      return { statusCode: 404, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Room not found' }) };
    }

    if (room.members.length >= room.maxPlayers) {
      return { statusCode: 409, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Room is full' }) };
    }

    if (room.isPrivate && code !== roomCode) {
      return { statusCode: 403, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Invalid room code' }) };
    }

    // Check if user is already in the room
    const alreadyMember = room.members.some(m => m.userId === userId);
    if (alreadyMember) {
      // Return the room as-is without adding again
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
        body: JSON.stringify({ room }),
      };
    }

    // Add member
    const avatarColors = [0xFFBF5AF2, 0xFF00FF88, 0xFFFF2D78, 0xFF00D4FF, 0xFFFFD700];
    const newMember = {
      userId,
      displayName: displayName || 'Player',
      avatarColor: avatarColors[room.members.length % avatarColors.length],
      totalXP: 0,
      streak: 0,
      badges: [],
      isHost: false,
      isConnected: true,
    };

    await ddb.send(new UpdateCommand({
      TableName: TABLE,
      Key: { roomCode },
      UpdateExpression: 'SET members = list_append(members, :newMember)',
      ExpressionAttributeValues: { ':newMember': [newMember] },
    }));

    // Return updated room
    const updated = await ddb.send(new GetCommand({ TableName: TABLE, Key: { roomCode } }));

    // Broadcast player_joined to all connections in this room
    const wsEndpoint = process.env.WS_ENDPOINT;
    if (wsEndpoint) {
      // Broadcast to room-level connections
      await broadcastToRoom(roomCode, {
        action: 'player_joined',
        data: { room: updated.Item, newMember },
      }, wsEndpoint);

      // Also broadcast to match-level connections (for room list updates)
      const matchId = room.matchId;
      if (matchId) {
        await broadcastToRoom(`match_${matchId}`, {
          action: 'room_updated',
          data: { room: updated.Item },
        }, wsEndpoint);
      }
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ room: updated.Item }),
    };
  } catch (err) {
    console.error('joinRoom error:', err);
    return { statusCode: 500, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Failed to join room' }) };
  }
};
