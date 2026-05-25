import 'dart:async';

import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../models/dfl_event_model.dart';

/// Service that parses DFL XML event data and streams events
/// one-by-one to simulate a live match feed.
///
/// In production, this will be replaced by a real-time feed
/// (SNS → Lambda → WebSocket → client).
class DflEventService {
  final _eventController = StreamController<DflEvent>.broadcast();
  Timer? _streamTimer;
  List<DflEvent> _events = [];
  int _currentIndex = 0;
  bool _isStreaming = false;

  /// Stream of live DFL events.
  Stream<DflEvent> get events => _eventController.stream;

  /// Whether the feed is currently streaming.
  bool get isStreaming => _isStreaming;

  /// All parsed events (for inspection/debugging).
  List<DflEvent> get allEvents => List.unmodifiable(_events);

  /// Current event index in the stream.
  int get currentIndex => _currentIndex;

  /// Load and parse the sample XML from assets.
  Future<void> loadSampleData() async {
    final xmlString = await rootBundle.loadString('assets/data/dfl_sample_events.xml');
    _events = parseXml(xmlString);
  }

  /// Parse DFL XML string into a list of events.
  List<DflEvent> parseXml(String xmlString) {
    final document = XmlDocument.parse(xmlString);
    final eventElements = document.findAllElements('Event');

    return eventElements.map((element) {
      final eventId = element.getAttribute('EventId') ?? '';
      final matchId = element.getAttribute('MatchId') ?? '';
      final eventTime = element.getAttribute('EventTime') ?? '';
      final xPos = double.tryParse(element.getAttribute('X-Position') ?? '') ?? 0;
      final yPos = double.tryParse(element.getAttribute('Y-Position') ?? '') ?? 0;

      // Determine event type from child elements
      String eventType = 'Unknown';
      String? team;
      String? player;
      String? recipient;
      String? evaluation;
      String? playOrigin;
      String? distance;
      String? height;
      String? gameSection;
      String? subType;

      // Check for KickOff
      final kickOff = element.getElement('KickOff');
      if (kickOff != null) {
        eventType = 'KickOff';
        gameSection = kickOff.getAttribute('GameSection');

        final play = kickOff.getElement('Play');
        if (play != null) {
          team = play.getAttribute('Team');
          player = play.getAttribute('Player');
          recipient = play.getAttribute('Recipient');
          evaluation = play.getAttribute('Evaluation');
          playOrigin = play.getAttribute('PlayOrigin');
          distance = play.getAttribute('Distance');
          height = play.getAttribute('Height');
          subType = _getPlaySubType(play);
        }
      }

      // Check for direct Play element
      final play = element.getElement('Play');
      if (play != null && kickOff == null) {
        eventType = 'Play';
        team = play.getAttribute('Team');
        player = play.getAttribute('Player');
        recipient = play.getAttribute('Recipient');
        evaluation = play.getAttribute('Evaluation');
        playOrigin = play.getAttribute('PlayOrigin');
        distance = play.getAttribute('Distance');
        height = play.getAttribute('Height');
        subType = _getPlaySubType(play);
      }

      // Check for Goal
      if (element.getElement('Goal') != null) {
        eventType = 'Goal';
        final goal = element.getElement('Goal')!;
        player = goal.getAttribute('Player');
        team = goal.getAttribute('Team');
      }

      // Check for Card
      if (element.getElement('Card') != null) {
        eventType = 'Card';
        final card = element.getElement('Card')!;
        player = card.getAttribute('Player');
        team = card.getAttribute('Team');
      }

      return DflEvent(
        eventId: eventId,
        matchId: matchId,
        eventTime: eventTime,
        xPosition: xPos,
        yPosition: yPos,
        eventType: eventType,
        team: team,
        player: player,
        recipient: recipient,
        evaluation: evaluation,
        playOrigin: playOrigin,
        distance: distance,
        height: height,
        gameSection: gameSection,
        subType: subType,
      );
    }).toList();
  }

  /// Get the sub-type of a Play element (Pass, Shot, Cross, etc.)
  String? _getPlaySubType(XmlElement play) {
    if (play.getElement('Pass') != null) return 'Pass';
    if (play.getElement('Shot') != null) return 'Shot';
    if (play.getElement('Cross') != null) return 'Cross';
    if (play.getElement('Header') != null) return 'Header';
    if (play.getElement('Tackle') != null) return 'Tackle';
    if (play.getElement('Freekick') != null) return 'Freekick';
    return null;
  }

  /// Start streaming events with a delay between each.
  /// [intervalSeconds] controls the pace (default 3s between events).
  void startStreaming({int intervalSeconds = 3}) {
    if (_events.isEmpty || _isStreaming) return;

    _isStreaming = true;
    _currentIndex = 0;

    _streamTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (_currentIndex >= _events.length) {
        stopStreaming();
        return;
      }

      _eventController.add(_events[_currentIndex]);
      _currentIndex++;
    });
  }

  /// Stop streaming events.
  void stopStreaming() {
    _streamTimer?.cancel();
    _streamTimer = null;
    _isStreaming = false;
  }

  /// Reset the stream to the beginning.
  void reset() {
    stopStreaming();
    _currentIndex = 0;
  }

  /// Dispose the service.
  void dispose() {
    stopStreaming();
    _eventController.close();
  }
}
