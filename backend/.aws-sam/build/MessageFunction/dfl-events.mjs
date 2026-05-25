import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';

const s3 = new S3Client({});
const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);

const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;
const WS_ENDPOINT = process.env.WS_ENDPOINT;

/**
 * Processes a DFL XML file from S3 and broadcasts events via WebSocket.
 * 
 * Expected event payload (from manual trigger or S3 notification):
 * {
 *   "bucket": "your-bucket-name",
 *   "key": "matches/DFL-MAT-111111/events.xml",
 *   "matchId": "DFL-MAT-111111",
 *   "roomCode": "A7X9K2",          // optional: target specific room
 *   "delayMs": 3000                 // delay between events (default 3s)
 * }
 * 
 * Future integrations (not implemented yet):
 * - AI/Bedrock: Process events to generate prediction questions
 * - SNS/SES: Send push notifications to offline users
 */
export const processEvents = async (event) => {
  try {
    const { bucket, key, matchId, roomCode, delayMs = 3000 } = event;

    if (!bucket || !key || !matchId) {
      return { statusCode: 400, body: JSON.stringify({ error: 'bucket, key, and matchId are required' }) };
    }

    // 1. Read XML from S3
    const s3Response = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const xmlString = await s3Response.Body.transformToString();

    // 2. Parse XML events (simple regex-based extraction for XML)
    const events = parseXmlEvents(xmlString, matchId);
    console.log(`Parsed ${events.length} events from ${key}`);

    if (events.length === 0) {
      return { statusCode: 200, body: JSON.stringify({ message: 'No events found', eventsProcessed: 0 }) };
    }

    // 3. Get WebSocket connections for this room/match
    const targetRoomCode = roomCode || `match_${matchId}`;
    const connections = await getConnections(targetRoomCode);
    console.log(`Found ${connections.length} connections for ${targetRoomCode}`);

    // Also get room-level connections if roomCode is specified
    let roomConnections = [];
    if (roomCode) {
      roomConnections = await getConnections(roomCode);
    }

    const allConnections = [...connections, ...roomConnections];

    // 4. Stream events with delay
    for (let i = 0; i < events.length; i++) {
      const dflEvent = events[i];

      // TODO: AI/Bedrock integration point
      // const question = await generateQuestionFromEvent(dflEvent);
      // If question generated, broadcast it separately

      // Broadcast raw event to all connections
      const message = {
        action: 'dfl_event',
        data: {
          event: dflEvent,
          eventIndex: i + 1,
          totalEvents: events.length,
          // placeholder for AI-generated content
          // question: null,
        },
      };

      await broadcastToConnections(allConnections, message);

      // TODO: Notification integration point
      // If user is offline, queue notification via SNS/SES
      // await notifyOfflineUsers(matchId, dflEvent);

      // Delay between events (simulate real-time feed)
      if (i < events.length - 1 && delayMs > 0) {
        await sleep(delayMs);
      }
    }

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Events processed successfully',
        eventsProcessed: events.length,
        connectionsNotified: allConnections.length,
      }),
    };
  } catch (err) {
    console.error('processEvents error:', err);
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};

/**
 * Parse DFL XML and extract events as structured objects.
 */
function parseXmlEvents(xmlString, matchId) {
  const events = [];
  // Match each <Event ...>...</Event> block
  const eventRegex = /<Event\s([^>]+)>([\s\S]*?)<\/Event>/g;
  let match;

  while ((match = eventRegex.exec(xmlString)) !== null) {
    const attrs = parseAttributes(match[1]);
    const innerXml = match[2];

    const event = {
      eventId: attrs['EventId'] || '',
      matchId: attrs['MatchId'] || matchId,
      eventTime: attrs['EventTime'] || '',
      xPosition: parseFloat(attrs['X-Position'] || '0'),
      yPosition: parseFloat(attrs['Y-Position'] || '0'),
    };

    // Determine event type
    if (innerXml.includes('<KickOff')) {
      event.eventType = 'KickOff';
      const gsMatch = innerXml.match(/GameSection="([^"]+)"/);
      event.gameSection = gsMatch ? gsMatch[1] : null;
    } else if (innerXml.includes('<Goal')) {
      event.eventType = 'Goal';
    } else if (innerXml.includes('<Card')) {
      event.eventType = 'Card';
    } else if (innerXml.includes('<Play')) {
      event.eventType = 'Play';
    } else {
      event.eventType = 'Unknown';
    }

    // Extract Play attributes
    const playMatch = innerXml.match(/<Play\s([^>]+)/);
    if (playMatch) {
      const playAttrs = parseAttributes(playMatch[1]);
      event.team = playAttrs['Team'] || null;
      event.player = playAttrs['Player'] || null;
      event.recipient = playAttrs['Recipient'] || null;
      event.evaluation = playAttrs['Evaluation'] || null;
      event.distance = playAttrs['Distance'] || null;
      event.height = playAttrs['Height'] || null;
      event.playOrigin = playAttrs['PlayOrigin'] || null;
    }

    // Determine sub-type
    if (innerXml.includes('<Pass')) event.subType = 'Pass';
    else if (innerXml.includes('<Shot')) event.subType = 'Shot';
    else if (innerXml.includes('<Cross')) event.subType = 'Cross';
    else if (innerXml.includes('<Header')) event.subType = 'Header';
    else if (innerXml.includes('<Tackle')) event.subType = 'Tackle';

    // Generate human-readable summary
    event.summary = generateSummary(event);

    events.push(event);
  }

  return events;
}

function generateSummary(event) {
  const playerShort = event.player ? event.player.split('-').pop() : '?';
  const recipientShort = event.recipient ? event.recipient.split('-').pop() : '';

  switch (event.eventType) {
    case 'KickOff':
      return `⚽ Kick Off! (${event.gameSection || 'unknown'})`;
    case 'Goal':
      return `🎉 GOAL! Scored by ${playerShort}`;
    case 'Card':
      return `🟨 Card for ${playerShort}`;
    case 'Play': {
      const result = event.evaluation === 'successfullyCompleted' ? '✓' : '✗';
      const type = event.subType || 'Play';
      return `${result} ${type} by ${playerShort} → ${recipientShort} (${event.distance || '?'}, ${event.height || '?'})`;
    }
    default:
      return `📋 ${event.eventType} (${playerShort})`;
  }
}

function parseAttributes(attrString) {
  const attrs = {};
  const regex = /(\S+)="([^"]+)"/g;
  let m;
  while ((m = regex.exec(attrString)) !== null) {
    attrs[m[1]] = m[2];
  }
  return attrs;
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
  if (connections.length === 0 || !WS_ENDPOINT) return;

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

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
