import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class LimitlessTournament {
  final String id;
  final String name;
  final String date;
  final String country;
  final int? players;
  final String winner;
  final String format;

  const LimitlessTournament({
    required this.id,
    required this.name,
    required this.date,
    required this.country,
    required this.players,
    required this.winner,
    required this.format,
  });

  String get url => 'https://limitlesstcg.com/tournaments/$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': date,
        'country': country,
        'players': players,
        'winner': winner,
        'format': format,
      };

  factory LimitlessTournament.fromJson(Map<String, dynamic> json) =>
      LimitlessTournament(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        country: json['country']?.toString() ?? '',
        players: int.tryParse(json['players']?.toString() ?? ''),
        winner: json['winner']?.toString() ?? '',
        format: json['format']?.toString() ?? '',
      );
}

@immutable
class LimitlessStanding {
  final int? placing;
  final String player;
  final String country;
  final String deck;
  final String decklistUrl;

  const LimitlessStanding({
    required this.placing,
    required this.player,
    required this.country,
    required this.deck,
    required this.decklistUrl,
  });

  Map<String, dynamic> toJson() => {
        'placing': placing,
        'player': player,
        'country': country,
        'deck': deck,
        'decklistUrl': decklistUrl,
      };

  factory LimitlessStanding.fromJson(Map<String, dynamic> json) =>
      LimitlessStanding(
        placing: int.tryParse(json['placing']?.toString() ?? ''),
        player: json['player']?.toString() ?? '',
        country: json['country']?.toString() ?? '',
        deck: json['deck']?.toString() ?? '',
        decklistUrl: json['decklistUrl']?.toString() ?? '',
      );
}


@immutable
class LimitlessDeckCard {
  final int quantity;
  final String name;
  final String number;
  final String collectionId;
  final String collectionName;

  const LimitlessDeckCard({
    required this.quantity,
    required this.name,
    required this.number,
    required this.collectionId,
    required this.collectionName,
  });
}

/// Reads the public, server-rendered pages of the main Limitless TCG database.
/// It intentionally does not call play.limitlesstcg.com or its tournament API.
class LimitlessTcgService {
  LimitlessTcgService({http.Client? client}) : _client = client ?? http.Client();

  static const String _baseUrl = 'https://limitlesstcg.com';
  static const String _eventsCacheKey = 'limitless_events_cache_v1';
  final http.Client _client;

  Future<String> _getPage(Uri uri) async {
    final response = await _client
        .get(uri, headers: const {
          'User-Agent': 'PokemonTCGManager/1.0 (public tournament database reader)',
          'Accept': 'text/html,application/xhtml+xml',
        })
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Limitless respondeu HTTP ${response.statusCode}.');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<List<LimitlessTournament>> fetchTournaments({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final cached = prefs.getString(_eventsCacheKey);
      if (cached != null) {
        try {
          final list = (jsonDecode(cached) as List)
              .whereType<Map>()
              .map((item) => LimitlessTournament.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .where((item) => item.id.isNotEmpty)
              .toList();
          if (list.isNotEmpty) return list;
        } catch (_) {
          // A cache inválida é ignorada e reconstruída pela próxima resposta.
        }
      }
    }

    final html = await _getPage(Uri.parse('$_baseUrl/tournaments'));
    final tournaments = parseTournamentList(html);
    if (tournaments.isEmpty) {
      throw Exception('A página abriu, mas nenhum torneio foi reconhecido.');
    }
    await prefs.setString(
      _eventsCacheKey,
      jsonEncode(tournaments.map((item) => item.toJson()).toList()),
    );
    return tournaments;
  }

  Future<List<LimitlessStanding>> fetchStandings(String tournamentId) async {
    if (!RegExp(r'^\d+$').hasMatch(tournamentId)) {
      throw ArgumentError.value(tournamentId, 'tournamentId');
    }
    final cacheKey = 'limitless_standings_${tournamentId}_v1';
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final list = (jsonDecode(cached) as List)
            .whereType<Map>()
            .map((item) => LimitlessStanding.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {
        // Ignora cache danificada.
      }
    }

    final page = await _getPage(
      Uri.parse('$_baseUrl/tournaments/$tournamentId'),
    );
    final standings = parseStandings(page);
    if (standings.isNotEmpty) {
      await prefs.setString(
        cacheKey,
        jsonEncode(standings.map((item) => item.toJson()).toList()),
      );
    }
    return standings;
  }


  Future<List<LimitlessDeckCard>> fetchDecklist(String decklistUrl) async {
    final uri = Uri.tryParse(decklistUrl);
    if (uri == null ||
        uri.host != 'limitlesstcg.com' ||
        !uri.path.startsWith('/decks/list/')) {
      throw ArgumentError.value(decklistUrl, 'decklistUrl');
    }
    final html = await _getPage(uri);
    return parseDecklist(html);
  }

  @visibleForTesting
  static List<LimitlessDeckCard> parseDecklist(String source) {
    final document = html_parser.parse(source);
    final cards = <LimitlessDeckCard>[];
    final seen = <String>{};

    // Supports both legacy table rows and the current grouped card-link layout.
    // Limitless renders current public decklists as card links inside grouped
    // sections, not consistently as table rows. Read every card link and
    // recover its quantity from the link or its nearest text container.
    for (final link in document.querySelectorAll('a[href*="/cards/"]')) {
      final href = link.attributes['href'] ?? '';
      final uri = Uri.tryParse(href);
      final path = uri?.pathSegments ?? const <String>[];
      if (path.length < 3 || path.first != 'cards') continue;

      final linkText = link.text.replaceAll(RegExp(r'\\s+'), ' ').trim();
      var quantity = 0;
      var name = '';

      final linkMatch =
          RegExp(r'^(\\d+)\\s+(.+)$').firstMatch(linkText);
      if (linkMatch != null) {
        quantity = int.tryParse(linkMatch.group(1) ?? '') ?? 0;
        name = linkMatch.group(2)?.trim() ?? '';
      } else {
        // Some layouts place the count next to the anchor rather than inside it.
        dom.Element? ancestor = link.parent;
        for (var depth = 0; ancestor != null && depth < 4; depth++) {
          final text = ancestor.text.replaceAll(RegExp(r'\\s+'), ' ').trim();
          final match = RegExp(r'^(\\d+)\\s+(.+)$').firstMatch(text);
          if (match != null) {
            quantity = int.tryParse(match.group(1) ?? '') ?? 0;
            final remainder = match.group(2)?.trim() ?? '';
            name = linkText.isNotEmpty ? linkText : remainder;
            break;
          }
          ancestor = ancestor.parent;
        }
      }

      if (quantity < 1 || quantity > 60 || name.isEmpty) continue;

      final number = path.last;
      final collectionId = path[path.length - 2];
      final key = '$name|$number|$collectionId';
      if (!seen.add(key)) continue;

      cards.add(LimitlessDeckCard(
        quantity: quantity,
        name: name,
        number: number,
        collectionId: collectionId,
        collectionName: '',
      ));
    }
    return cards;
  }

  @visibleForTesting
  static List<LimitlessTournament> parseTournamentList(String source) {
    final document = html_parser.parse(source);
    final results = <LimitlessTournament>[];
    final seen = <String>{};

    for (final row in document.querySelectorAll('table tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4) continue;

      dom.Element? tournamentLink;
      for (final anchor in row.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'] ?? '';
        if (RegExp(r'^/tournaments/\d+/?$').hasMatch(href)) {
          tournamentLink = anchor;
          break;
        }
      }
      if (tournamentLink == null) continue;

      final href = tournamentLink.attributes['href']!;
      final id = RegExp(r'/tournaments/(\d+)').firstMatch(href)?.group(1) ?? '';
      if (id.isEmpty || !seen.add(id)) continue;

      final texts = cells.map((cell) => cell.text.trim()).toList();
      final country = row.querySelector('img[alt]')?.attributes['alt'] ?? '';
      final playerCounts = texts
          .map((value) => int.tryParse(value.replaceAll(',', '').replaceAll('.', '')))
          .whereType<int>()
          .toList();
      final format = texts.firstWhere(
        (value) => value.toLowerCase().contains('standard') ||
            value.toLowerCase().contains('expanded') ||
            value.toLowerCase().contains('gym'),
        orElse: () => '',
      );
      final winner = cells.isNotEmpty ? cells.last.text.trim() : '';

      results.add(LimitlessTournament(
        id: id,
        name: tournamentLink.text.trim(),
        date: cells.first.text.trim(),
        country: country,
        players: playerCounts.isEmpty ? null : playerCounts.last,
        winner: winner,
        format: format,
      ));
    }
    return results;
  }

  @visibleForTesting
  static List<LimitlessStanding> parseStandings(String source) {
    final document = html_parser.parse(source);
    final results = <LimitlessStanding>[];
    final seen = <String>{};

    for (final row in document.querySelectorAll('table tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 3) continue;
      final placing = int.tryParse(cells.first.text.trim().replaceAll(RegExp(r'[^0-9]'), ''));
      if (placing == null) continue;

      final playerAnchor = row.querySelector('a[href*="/players/"]');
      final player = playerAnchor?.text.trim() ??
          (cells.length > 1 ? cells[1].text.trim() : '');
      if (player.isEmpty || !seen.add('$placing|$player')) continue;

      final deckAnchor = row.querySelector('a[href*="/decks/"]');
      final decklistAnchor = row.querySelector('a[href*="/decks/list/"]');
      final country = row.querySelector('img[alt]')?.attributes['alt'] ?? '';

      results.add(LimitlessStanding(
        placing: placing,
        player: player,
        country: country,
        deck: deckAnchor?.text.trim() ?? '',
        decklistUrl: decklistAnchor == null
            ? ''
            : Uri.parse(_baseUrl).resolve(
                decklistAnchor.attributes['href'] ?? '',
              ).toString(),
      ));
    }
    return results;
  }

  void dispose() => _client.close();
}
