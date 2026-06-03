import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, DeleteCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;

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
