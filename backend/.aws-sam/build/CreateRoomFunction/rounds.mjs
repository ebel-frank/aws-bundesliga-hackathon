import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const TABLE = process.env.ROUNDS_TABLE;

export const getRounds = async (event) => {
  try {
    const matchId = event.pathParameters?.matchId;
    if (!matchId) return { statusCode: 400, body: JSON.stringify({ error: 'matchId required' }) };

    const result = await ddb.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'matchId = :matchId',
      ExpressionAttributeValues: { ':matchId': matchId },
      ScanIndexForward: true, // sort by roundNumber ascending
    }));

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ rounds: result.Items || [] }),
    };
  } catch (err) {
    console.error('getRounds error:', err);
    return { statusCode: 500, headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify({ error: 'Failed to fetch rounds' }) };
  }
};
