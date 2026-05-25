import unittest

from ai_core.event_normalizer import normalize_event, normalize_event_xml


class EventNormalizerTest(unittest.TestCase):
    def test_normalize_event_aliases_common_fields(self):
        event = normalize_event(
            {
                "id": "42",
                "type": "YellowCard",
                "time": "31",
                "teamName": "Home FC",
                "playerName": "Player 4",
            }
        )

        self.assertEqual(event["event_id"], "42")
        self.assertEqual(event["event_type"], "YELLOW_CARD")
        self.assertEqual(event["minute"], 31)
        self.assertEqual(event["team"], "Home FC")

    def test_normalize_dfl_xml_event(self):
        xml = """
        <Event EventId="18902400000006" X-Position="52.30" MatchId="DFL-MAT-111111" Y-Position="35.30">
          <KickOff TeamLeft="DFL-CLU-000002" TeamRight="DFL-CLU-000001" GameSection="firstHalf">
            <Play Recipient="DFL-OBJ-000025" Team="DFL-CLU-000002" Height="high" Distance="short" Player="DFL-OBJ-000029" Evaluation="successfullyCompleted">
              <Pass FreeKickLayup="false"/>
            </Play>
          </KickOff>
        </Event>
        """
        event = normalize_event_xml(xml)

        self.assertEqual(event["event_id"], "18902400000006")
        self.assertEqual(event["match_id"], "DFL-MAT-111111")
        self.assertEqual(event["event_type"], "KICK_OFF")
        self.assertEqual(event["team"], "DFL-CLU-000002")
        self.assertEqual(event["player"], "DFL-OBJ-000029")
        self.assertEqual(event["recipient"], "DFL-OBJ-000025")


if __name__ == "__main__":
    unittest.main()
