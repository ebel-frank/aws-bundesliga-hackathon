import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

const s3 = new S3Client({});
const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);
const lambdaClient = new LambdaClient({});

const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;
const WS_ENDPOINT = process.env.WS_ENDPOINT;
const QUESTION_TRIGGER_FUNCTION = process.env.QUESTION_TRIGGER_FUNCTION;

/**
 * Processes DFL match data from S3 and broadcasts enriched events via WebSocket.
 * 
 * Expected event payload:
 * {
 *   "bucket": "your-bucket-name",
 *   "eventsKey": "Match-Events/Events_Anonym.xml",
 *   "matchInfoKey": "Match-Events/MatchInformations_Anonym.xml",  // optional
 *   "matchId": "DFL-MAT-111111",
 *   "roomCode": "A7X9K2",          // target room for WebSocket broadcast
 *   "delayMs": 3000                 // delay between events (default 3s)
 * }
 * 
 * Flow:
 * 1. Load MatchInformations (if provided) → build player/team lookup
 * 2. Load Events → parse and enrich with player names
 * 3. Stream enriched events via WebSocket with delay
 * 
 * Future integrations (not implemented yet):
 * - AI/Bedrock: Process events to generate prediction questions
 * - SNS/SES: Send push notifications to offline users
 */
export const processEvents = async (event) => {
  try {
    const { bucket, eventsKey, matchInfoKey, matchId, roomCode, delayMs = 3000 } = event;

    // Support legacy 'key' parameter
    const effectiveEventsKey = eventsKey || event.key;

    if (!bucket || !effectiveEventsKey || !matchId) {
      return { statusCode: 400, body: JSON.stringify({ error: 'bucket, eventsKey (or key), and matchId are required' }) };
    }

    // 1. Load match information for player/team name resolution
    let playerLookup = {};
    let teamLookup = {};
    let matchInfo = null;

    if (matchInfoKey) {
      console.log(`Loading match info from s3://${bucket}/${matchInfoKey}`);
      const infoResponse = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: matchInfoKey }));
      const infoXml = await infoResponse.Body.transformToString();
      const parsed = parseMatchInformation(infoXml);
      playerLookup = parsed.players;
      teamLookup = parsed.teams;
      matchInfo = parsed.matchInfo;
      console.log(`Loaded ${Object.keys(playerLookup).length} players, ${Object.keys(teamLookup).length} teams`);
    }

    // 2. Read and parse events XML from S3
    console.log(`Loading events from s3://${bucket}/${effectiveEventsKey}`);
    const eventsResponse = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: effectiveEventsKey }));
    const xmlString = await eventsResponse.Body.transformToString();
    const events = parseXmlEvents(xmlString, matchId, playerLookup, teamLookup);
    console.log(`Parsed ${events.length} events`);

    if (events.length === 0) {
      return { statusCode: 200, body: JSON.stringify({ message: 'No events found', eventsProcessed: 0 }) };
    }

    // 3. Get WebSocket connections
    const targetRoomCode = roomCode || `match_${matchId}`;
    const connections = await getConnections(targetRoomCode);

    // Also get match-level connections
    const matchConnections = roomCode ? await getConnections(`match_${matchId}`) : [];
    const allConnections = [...connections, ...matchConnections];
    console.log(`Broadcasting to ${allConnections.length} connections`);

    // 4. Send match info first (so clients know the context)
    if (matchInfo) {
      await broadcastToConnections(allConnections, {
        action: 'match_info',
        data: { matchInfo, players: playerLookup, teams: teamLookup },
      });
    }

    // 5. Stream events with delay
    for (let i = 0; i < events.length; i++) {
      const dflEvent = events[i];

      // Invoke Question Trigger Lambda (async — doesn't block streaming)
      if (QUESTION_TRIGGER_FUNCTION) {
        await lambdaClient.send(new InvokeCommand({
          FunctionName: QUESTION_TRIGGER_FUNCTION,
          InvocationType: 'Event', // async, fire-and-forget
          Payload: Buffer.from(JSON.stringify({
            matchId,
            roomCode: targetRoomCode,
            event: dflEvent,
            matchInfo,
            playerLookup,
            teamLookup,
          })),
        }));
      }

      // TODO: Notification integration point
      // await notifyOfflineUsers(matchId, dflEvent);

      const message = {
        action: 'dfl_event',
        data: {
          event: dflEvent,
          eventIndex: i + 1,
          totalEvents: events.length,
        },
      };

      await broadcastToConnections(allConnections, message);

      // Delay between events
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
        playersLoaded: Object.keys(playerLookup).length,
      }),
    };
  } catch (err) {
    console.error('processEvents error:', err);
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};

/**
 * Parse MatchInformations XML to extract player names, team info, and match metadata.
 */
function parseMatchInformation(xmlString) {
  const players = {};
  const teams = {};
  const matchInfo = {};

  // Extract General match info
  const generalMatch = xmlString.match(/<General\s([^>]+)/);
  if (generalMatch) {
    const attrs = parseAttributes(generalMatch[1]);
    matchInfo.competitionName = attrs['CompetitionName'] || '';
    matchInfo.matchDay = attrs['MatchDay'] || '';
    matchInfo.matchId = attrs['MatchId'] || '';
    matchInfo.homeTeamName = attrs['HomeTeamName'] || '';
    matchInfo.homeTeamId = attrs['HomeTeamId'] || '';
    matchInfo.homeTeamCode = attrs['HomeTeamThreeLetterCode'] || '';
    matchInfo.guestTeamName = attrs['GuestTeamName'] || '';
    matchInfo.guestTeamId = attrs['GuestTeamId'] || '';
    matchInfo.guestTeamCode = attrs['GuestTeamThreeLetterCode'] || '';
    matchInfo.result = attrs['Result'] || '';
    matchInfo.kickoffTime = attrs['KickoffTime'] || '';
    matchInfo.stadiumName = '';
    matchInfo.season = attrs['Season'] || '';
  }

  // Extract stadium
  const envMatch = xmlString.match(/<Environment\s([^>]+)/);
  if (envMatch) {
    const attrs = parseAttributes(envMatch[1]);
    matchInfo.stadiumName = attrs['StadiumName'] || '';
    matchInfo.spectators = attrs['NumberOfSpectators'] || '';
  }

  // Extract teams
  const teamRegex = /<Team\s([^>]+)>/g;
  let tm;
  while ((tm = teamRegex.exec(xmlString)) !== null) {
    const attrs = parseAttributes(tm[1]);
    const teamId = attrs['TeamId'];
    if (teamId) {
      teams[teamId] = {
        teamId,
        teamName: attrs['TeamName'] || '',
        shortName: attrs['ShortName'] || '',
        threeLetterCode: attrs['ThreeLetterCode'] || '',
        role: attrs['Role'] || '',
        lineUp: attrs['LineUp'] || '',
      };
    }
  }

  // Extract players
  const playerRegex = /<Player\s([^>\/]+)\/?>/g;
  let pm;
  while ((pm = playerRegex.exec(xmlString)) !== null) {
    const attrs = parseAttributes(pm[1]);
    const personId = attrs['PersonId'];
    if (personId) {
      players[personId] = {
        personId,
        firstName: attrs['FirstName'] || '',
        lastName: attrs['LastName'] || '',
        shortName: attrs['Shortname'] || '',
        shirtNumber: attrs['ShirtNumber'] || '',
        position: attrs['PlayingPosition'] || '',
        starting: attrs['Starting'] === 'true',
        teamLeader: attrs['TeamLeader'] === 'true',
      };
    }
  }

  return { players, teams, matchInfo };
}

/**
 * Parse DFL Events XML and enrich with player/team names.
 */
function parseXmlEvents(xmlString, matchId, playerLookup, teamLookup) {
  const events = [];
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
    } else if (innerXml.includes('<Substitution')) {
      event.eventType = 'Substitution';
    } else if (innerXml.includes('<Play')) {
      event.eventType = 'Play';
    } else {
      event.eventType = 'Unknown';
    }

    // Extract Play attributes
    const playMatch = innerXml.match(/<Play\s([^>]+)/);
    if (playMatch) {
      const playAttrs = parseAttributes(playMatch[1]);
      event.teamId = playAttrs['Team'] || null;
      event.playerId = playAttrs['Player'] || null;
      event.recipientId = playAttrs['Recipient'] || null;
      event.evaluation = playAttrs['Evaluation'] || null;
      event.distance = playAttrs['Distance'] || null;
      event.height = playAttrs['Height'] || null;
      event.playOrigin = playAttrs['PlayOrigin'] || null;
      event.penaltyBox = playAttrs['PenaltyBox'] === 'true';
    }

    // Determine sub-type
    if (innerXml.includes('<Pass')) event.subType = 'Pass';
    else if (innerXml.includes('<Shot')) event.subType = 'Shot';
    else if (innerXml.includes('<Cross')) event.subType = 'Cross';
    else if (innerXml.includes('<Header')) event.subType = 'Header';
    else if (innerXml.includes('<Tackle')) event.subType = 'Tackle';
    else if (innerXml.includes('<Freekick')) event.subType = 'Freekick';
    else if (innerXml.includes('<Corner')) event.subType = 'Corner';
    else if (innerXml.includes('<ThrowIn')) event.subType = 'ThrowIn';

    // Enrich with player/team names
    event.playerName = resolvePlayerName(event.playerId, playerLookup);
    event.recipientName = resolvePlayerName(event.recipientId, playerLookup);
    event.teamName = resolveTeamName(event.teamId, teamLookup);

    // Generate human-readable summary
    event.summary = generateSummary(event);

    events.push(event);
  }

  return events;
}

function resolvePlayerName(playerId, lookup) {
  if (!playerId || !lookup[playerId]) return null;
  return lookup[playerId].shortName || `${lookup[playerId].firstName} ${lookup[playerId].lastName}`;
}

function resolveTeamName(teamId, lookup) {
  if (!teamId || !lookup[teamId]) return null;
  return lookup[teamId].shortName || lookup[teamId].teamName;
}

function generateSummary(event) {
  const player = event.playerName || (event.playerId ? event.playerId.split('-').pop() : '?');
  const recipient = event.recipientName || (event.recipientId ? event.recipientId.split('-').pop() : '');
  const team = event.teamName || '';

  switch (event.eventType) {
    case 'KickOff':
      return `⚽ Kick Off! (${event.gameSection || 'unknown'})`;
    case 'Goal':
      return `🎉 GOAL! ${player} scores for ${team}!`;
    case 'Card':
      return `🟨 Card for ${player} (${team})`;
    case 'Substitution':
      return `🔄 Substitution: ${player} (${team})`;
    case 'Play': {
      const result = event.evaluation === 'successfullyCompleted' ? '✓' : '✗';
      const type = event.subType || 'Play';
      return `${result} ${type}: ${player} → ${recipient} (${event.distance || '?'}, ${team})`;
    }
    default:
      return `📋 ${event.eventType}: ${player}`;
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
