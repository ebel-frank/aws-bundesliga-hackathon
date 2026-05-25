/**
 * Trigger script to invoke the DFL Events Lambda manually.
 * 
 * Usage:
 *   node trigger-dfl-events.mjs <bucket> <eventsKey> <matchId> [options]
 * 
 * Options:
 *   --match-info <key>    Path to MatchInformations XML in S3
 *   --room <roomCode>     Target specific room for broadcast
 *   --delay <ms>          Delay between events in ms (default 3000)
 * 
 * Examples:
 *   node trigger-dfl-events.mjs lpa-dfl-data Match-Events/Events_Anonym.xml DFL-MAT-111111 --match-info Match-Events/MatchInformations_Anonym.xml --room A7X9K2
 *   node trigger-dfl-events.mjs lpa-dfl-data Match-Events/Events_Anonym.xml DFL-MAT-111111 --delay 2000
 */

import { LambdaClient, InvokeCommand, ListFunctionsCommand } from '@aws-sdk/client-lambda';

const lambda = new LambdaClient({ region: 'us-east-1' });

// Parse arguments
const args = process.argv.slice(2);
const bucket = args[0];
const eventsKey = args[1];
const matchId = args[2];

if (!bucket || !eventsKey || !matchId) {
  console.error('Usage: node trigger-dfl-events.mjs <bucket> <eventsKey> <matchId> [options]');
  console.error('');
  console.error('Options:');
  console.error('  --match-info <key>    Path to MatchInformations XML in S3');
  console.error('  --room <roomCode>     Target specific room for broadcast');
  console.error('  --delay <ms>          Delay between events in ms (default 3000)');
  console.error('');
  console.error('Example:');
  console.error('  node trigger-dfl-events.mjs lpa-dfl-data Match-Events/Events_Anonym.xml DFL-MAT-111111 --match-info Match-Events/MatchInformations_Anonym.xml --room A7X9K2');
  process.exit(1);
}

// Parse optional flags
let matchInfoKey = null;
let roomCode = null;
let delayMs = 3000;

for (let i = 3; i < args.length; i++) {
  if (args[i] === '--match-info' && args[i + 1]) { matchInfoKey = args[++i]; }
  else if (args[i] === '--room' && args[i + 1]) { roomCode = args[++i]; }
  else if (args[i] === '--delay' && args[i + 1]) { delayMs = parseInt(args[++i], 10); }
}

const payload = {
  bucket,
  eventsKey,
  matchId,
  ...(matchInfoKey && { matchInfoKey }),
  ...(roomCode && { roomCode }),
  delayMs,
};

console.log('Payload:', JSON.stringify(payload, null, 2));

// Find the DFL function name
try {
  console.log('Looking up DflEventsFunction...');
  const listResponse = await lambda.send(new ListFunctionsCommand({}));
  const dflFunction = listResponse.Functions.find(f => f.FunctionName.includes('DflEvents'));

  if (!dflFunction) {
    console.error('Could not find DflEventsFunction. Make sure you have deployed with `sam deploy`.');
    process.exit(1);
  }

  console.log(`Found: ${dflFunction.FunctionName}`);
  console.log('Invoking (async)...');

  const response = await lambda.send(new InvokeCommand({
    FunctionName: dflFunction.FunctionName,
    InvocationType: 'Event', // async — returns immediately
    Payload: Buffer.from(JSON.stringify(payload)),
  }));

  console.log(`✓ Lambda invoked (StatusCode: ${response.StatusCode})`);
  console.log('Events will stream to connected WebSocket clients over the next few seconds.');
} catch (err) {
  console.error('Error:', err.message);
  console.error('');
  console.error('Alternative: invoke directly with AWS CLI:');
  const cliPayload = JSON.stringify(payload).replace(/"/g, '\\"');
  console.error(`  aws lambda invoke --function-name arena-app-DflEventsFunction-XXXX --invocation-type Event --cli-binary-format raw-in-base64-out --payload "${cliPayload}" /dev/null --region us-east-1`);
}
