/**
 * Seed script for DynamoDB tables.
 * Run: node seed.mjs
 * Requires AWS credentials configured (aws configure).
 */
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({ region: 'us-east-1' });
const ddb = DynamoDBDocumentClient.from(client);

const MATCHES_TABLE = 'lpa-matches';
const ROUNDS_TABLE = 'lpa-rounds';

// ─── Sample Matches ─────────────────────────────────────────────

const matches = [
  {
    // ── Real anonymised DFL fixture (the live-streamed match) ──
    // Source: MatchInformations_Anonym.xml in the hackathon S3 bucket.
    // Anonymised as "FC Team" vs "Club" (DFL-CLU-000001/2); displayed via the
    // same team-name overrides the question engine uses (Bayern Munich / Hamburger SV).
    // Bundesliga MatchDay 1, Season 2025/2026, kickoff 2025-01-01 16:30, final 5:0.
    matchId: 'DFL-MAT-000001',
    homeTeam: 'Bayern Munich',
    awayTeam: 'Hamburger SV',
    homeTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
    awayTeamBadge: 'assets/icons/germany_hamburger-sv.football-logos.svg',
    league: 'Bundesliga · Matchday 1',
    matchTime: '16:30',
    matchDate: 'Wed, Jan 1',
    status: 'live',
    roomCount: 0,
  },
  {
    matchId: 'm2',
    homeTeam: 'Eintracht Frankfurt',
    awayTeam: 'Bayern Munich',
    homeTeamBadge: 'assets/icons/germany_eintracht-frankfurt.football-logos.svg',
    awayTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
    league: 'Bundesliga',
    matchTime: '18:30',
    matchDate: 'Tomorrow',
    status: 'upcoming',
    roomCount: 0,
  },
  {
    matchId: 'm3',
    homeTeam: 'RB Leipzig',
    awayTeam: 'Bayern Munich',
    homeTeamBadge: 'assets/icons/germany_rb-leipzig.football-logos.svg',
    awayTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
    league: 'Bundesliga',
    matchTime: '15:30',
    matchDate: 'Sat, Jun 28',
    status: 'upcoming',
    roomCount: 0,
  },
  {
    matchId: 'm4',
    homeTeam: 'Bayer Leverkusen',
    awayTeam: 'Eintracht Frankfurt',
    homeTeamBadge: 'assets/icons/germany_bayer-leverkusen.football-logos.svg',
    awayTeamBadge: 'assets/icons/germany_eintracht-frankfurt.football-logos.svg',
    league: 'Bundesliga',
    matchTime: '20:30',
    matchDate: 'Sat, Jun 28',
    status: 'upcoming',
    roomCount: 0,
  },
  {
    matchId: 'm5',
    homeTeam: 'Bayern Munich',
    awayTeam: 'VfB Stuttgart',
    homeTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
    awayTeamBadge: 'assets/icons/germany_vfb-stuttgart.football-logos.svg',
    league: 'Bundesliga',
    matchTime: '15:30',
    matchDate: 'Sun, Jun 29',
    status: 'upcoming',
    roomCount: 0,
  },
];

// ─── Sample Rounds (per match) ──────────────────────────────────

const roundsPerMatch = {
  // Real anonymised fixture — answers reflect the actual 5:0 result.
  'DFL-MAT-000001': [
    { roundNumber: 1, questionText: 'Which team scores the first goal?', options: ['Bayern Munich', 'Hamburger SV'], correctAnswer: 'Bayern Munich', category: 'goalscorer' },
    { roundNumber: 2, questionText: 'Total goals over/under 2.5?', options: ['Over 2.5', 'Under 2.5'], correctAnswer: 'Over 2.5', category: 'overunder' },
    { roundNumber: 3, questionText: 'Will Hamburger SV score?', options: ['Yes', 'No'], correctAnswer: 'No', category: 'cards' },
    { roundNumber: 4, questionText: 'Final result?', options: ['Bayern Win', 'Draw', 'Hamburg Win'], correctAnswer: 'Bayern Win', category: 'result' },
    { roundNumber: 5, questionText: 'How many goals will Bayern Munich score?', options: ['2 or fewer', '3', '4', '5 or more'], correctAnswer: '5 or more', category: 'stats' },
  ],
  m2: [
    { roundNumber: 1, questionText: 'Who will score first?', options: ['Marmoush', 'Ekitiké', 'Kane', 'Musiala'], correctAnswer: 'Marmoush', category: 'goalscorer' },
    { roundNumber: 2, questionText: 'Total goals over/under 3.5?', options: ['Over 3.5', 'Under 3.5'], correctAnswer: 'Under 3.5', category: 'overunder' },
    { roundNumber: 3, questionText: 'First card color?', options: ['Yellow', 'Red', 'No card in first half'], correctAnswer: 'Yellow', category: 'cards' },
    { roundNumber: 4, questionText: 'Half-time result?', options: ['Frankfurt leads', 'Draw', 'Bayern leads'], correctAnswer: 'Draw', category: 'result' },
    { roundNumber: 5, questionText: 'Most passes completed?', options: ['Kimmich', 'Rode', 'Goretzka', 'Skhiri'], correctAnswer: 'Kimmich', category: 'stats' },
  ],
  m3: [
    { roundNumber: 1, questionText: 'First goalscorer?', options: ['Openda', 'Kane', 'Sané', 'Sesko'], correctAnswer: 'Kane', category: 'goalscorer' },
    { roundNumber: 2, questionText: 'Total corners over/under 9.5?', options: ['Over 9.5', 'Under 9.5'], correctAnswer: 'Over 9.5', category: 'overunder' },
    { roundNumber: 3, questionText: 'Which team gets a red card?', options: ['Leipzig', 'Bayern', 'Neither'], correctAnswer: 'Neither', category: 'cards' },
    { roundNumber: 4, questionText: 'Final result?', options: ['Leipzig Win', 'Draw', 'Bayern Win'], correctAnswer: 'Bayern Win', category: 'result' },
    { roundNumber: 5, questionText: 'Most tackles?', options: ['Upamecano', 'Orban', 'Kimmich', 'Laimer'], correctAnswer: 'Kimmich', category: 'stats' },
  ],
  m4: [
    { roundNumber: 1, questionText: 'First goal scorer?', options: ['Wirtz', 'Marmoush', 'Schick', 'Ekitiké'], correctAnswer: 'Wirtz', category: 'goalscorer' },
    { roundNumber: 2, questionText: 'Total goals over/under 2.5?', options: ['Over 2.5', 'Under 2.5'], correctAnswer: 'Over 2.5', category: 'overunder' },
    { roundNumber: 3, questionText: 'First booking?', options: ['Leverkusen player', 'Frankfurt player'], correctAnswer: 'Frankfurt player', category: 'cards' },
    { roundNumber: 4, questionText: 'Final result?', options: ['Leverkusen Win', 'Draw', 'Frankfurt Win'], correctAnswer: 'Leverkusen Win', category: 'result' },
    { roundNumber: 5, questionText: 'Most saves?', options: ['Hradecky', 'Trapp'], correctAnswer: 'Trapp', category: 'stats' },
  ],
  m5: [
    { roundNumber: 1, questionText: 'First goal?', options: ['Kane', 'Musiala', 'Guirassy', 'Undav'], correctAnswer: 'Kane', category: 'goalscorer' },
    { roundNumber: 2, questionText: 'Total goals over/under 3.5?', options: ['Over 3.5', 'Under 3.5'], correctAnswer: 'Over 3.5', category: 'overunder' },
    { roundNumber: 3, questionText: 'First yellow card team?', options: ['Bayern', 'Stuttgart'], correctAnswer: 'Stuttgart', category: 'cards' },
    { roundNumber: 4, questionText: 'Winner after 90 minutes?', options: ['Bayern', 'Draw', 'Stuttgart'], correctAnswer: 'Bayern', category: 'result' },
    { roundNumber: 5, questionText: 'Player with most shots?', options: ['Kane', 'Guirassy', 'Sané', 'Undav'], correctAnswer: 'Kane', category: 'stats' },
  ],
};

// ─── Seed Functions ─────────────────────────────────────────────

async function seedMatches() {
  console.log('Seeding matches...');
  for (const match of matches) {
    await ddb.send(new PutCommand({ TableName: MATCHES_TABLE, Item: match }));
    console.log(`  ✓ ${match.homeTeam} vs ${match.awayTeam}`);
  }
}

async function seedRounds() {
  console.log('Seeding rounds...');
  for (const [matchId, rounds] of Object.entries(roundsPerMatch)) {
    for (const round of rounds) {
      await ddb.send(new PutCommand({
        TableName: ROUNDS_TABLE,
        Item: {
          matchId,
          roundNumber: round.roundNumber,
          roundId: `${matchId}_r${round.roundNumber}`,
          questionText: round.questionText,
          options: round.options,
          correctAnswer: round.correctAnswer,
          category: round.category,
          timeLimitSeconds: 15,
        },
      }));
    }
    console.log(`  ✓ ${matchId}: ${rounds.length} rounds`);
  }
}

async function main() {
  console.log('🏟️  Live Prediction Arena — Seeding DynamoDB\n');
  await seedMatches();
  console.log('');
  await seedRounds();
  console.log('\n✅ Done! All data seeded successfully.');
}

main().catch(console.error);
