import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const TABLE = process.env.MATCHES_TABLE;

export const getMatches = async (event) => {
  try {
    const status = event.queryStringParameters?.status;

    let result;
    if (status) {
      result = await ddb.send(new QueryCommand({
        TableName: TABLE,
        IndexName: 'status-index',
        KeyConditionExpression: '#s = :status',
        ExpressionAttributeNames: { '#s': 'status' },
        ExpressionAttributeValues: { ':status': status },
      }));
    } else {
      result = await ddb.send(new ScanCommand({ TableName: TABLE }));
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ matches: result.Items || [] }),
    };
  } catch (err) {
    console.error('getMatches error:', err);
    return {
      statusCode: 500,
      headers: { 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ error: 'Failed to fetch matches' }),
    };
  }
};
