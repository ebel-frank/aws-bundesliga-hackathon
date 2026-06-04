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

/**
 * Remove a user from every room for `matchId` except `keepRoomCode`.
 * If a room becomes empty it is deleted; otherwise the updated member list is
 * persisted and broadcast so remaining players see the change.
 */
async function removeUserFromOtherRooms(matchId, userId, keepRoomCode, wsEndpoint) {
  if (!matchId || !userId) return;
  try {
    const res = await ddb.send(new QueryCommand({
      TableName: TABLE,
      IndexName: 'matchId-index',
      KeyConditionExpression: 'matchId = :matchId',
      ExpressionAttributeValues: { ':matchId': matchId },
    }));
    const rooms = res.Items || [];

    for (const r of rooms) {
      if (r.roomCode === keepRoomCode) continue;
      const isMember = (r.members || []).some(m => m.userId === userId);
      if (!isMember) continue;

      const remaining = r.members.filter(m => m.userId !== userId);

      if (remaining.length === 0) {
        // Room is now empty — delete it.
        await ddb.send(new DeleteCommand({ TableName: TABLE, Key: { roomCode: r.roomCode } }));
      } else {
        // If the host left, promote the first remaining member.
        if (r.hostUserId === userId) {
          remaining[0] = { ...remaining[0], isHost: true };
          r.hostUserId = remaining[0].userId;
        }
        await ddb.send(new UpdateCommand({
          TableName: TABLE,
          Key: { roomCode: r.roomCode },
          UpdateExpression: 'SET members = :m, hostUserId = :h',
          ExpressionAttributeValues: { ':m': remaining, ':h': r.hostUserId },
        }));
      }

      // Broadcast the change to the old room + the match list.
      if (wsEndpoint) {
        await broadcastToRoom(r.roomCode, {
          action: 'player_left',
          data: { roomCode: r.roomCode, userId },
        }, wsEndpoint);
        await broadcastToRoom(`match_${matchId}`, {
          action: 'room_updated',
          data: { roomCode: r.roomCode },
        }, wsEndpoint);
      }
    }
  } catch (err) {
    console.error('removeUserFromOtherRooms error:', err.message);
  }
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

    // Ensure the player is in only ONE room per match: remove them from any
    // other room for the same match before joining this one.
    await removeUserFromOtherRooms(room.matchId, userId, roomCode, process.env.WS_ENDPOINT);

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

export const leaveRoom = async (event) => {
  try {
    const roomCode = event.pathParameters?.roomCode;
    const body = JSON.parse(event.body || '{}');
    const { userId } = body;

    if (!roomCode || !userId) {
      return { statusCode: 400, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'roomCode and userId required' }) };
    }

    const result = await ddb.send(new GetCommand({ TableName: TABLE, Key: { roomCode } }));
    const room = result.Item;
    if (!room) {
      return { statusCode: 404, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Room not found' }) };
    }

    const remaining = (room.members || []).filter(m => m.userId !== userId);
    const wsEndpoint = process.env.WS_ENDPOINT;

    if (remaining.length === 0) {
      // Last member left — delete the room.
      await ddb.send(new DeleteCommand({ TableName: TABLE, Key: { roomCode } }));
    } else {
      let hostUserId = room.hostUserId;
      // Promote a new host if the host left.
      if (hostUserId === userId) {
        remaining[0] = { ...remaining[0], isHost: true };
        hostUserId = remaining[0].userId;
      }
      await ddb.send(new UpdateCommand({
        TableName: TABLE,
        Key: { roomCode },
        UpdateExpression: 'SET members = :m, hostUserId = :h',
        ExpressionAttributeValues: { ':m': remaining, ':h': hostUserId },
      }));
    }

    if (wsEndpoint) {
      await broadcastToRoom(roomCode, {
        action: 'player_left',
        data: { roomCode, userId },
      }, wsEndpoint);
      if (room.matchId) {
        await broadcastToRoom(`match_${room.matchId}`, {
          action: 'room_updated',
          data: { roomCode },
        }, wsEndpoint);
      }
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ success: true }),
    };
  } catch (err) {
    console.error('leaveRoom error:', err);
    return { statusCode: 500, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Failed to leave room' }) };
  }
};
