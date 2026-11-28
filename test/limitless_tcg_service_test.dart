import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_tcg_app/services/limitless_tcg_service.dart';

void main() {
  group('LimitlessTcgService HTML parsing', () {
    test('extracts tournament metadata from the main database table', () {
      const html = '''
        <html><body>
          <table>
            <tr>
              <th>Date</th><th>Country</th><th>Name</th>
              <th>Format</th><th>Players</th><th>Winner</th>
            </tr>
            <tr>
              <td>31 Oct 26</td>
              <td><img alt="PL" src="/flag.png"></td>
              <td><a href="/tournaments/584">Regional Gdańsk</a></td>
              <td>standard</td><td>1739</td><td>Aarni Karjala</td>
            </tr>
          </table>
        </body></html>
      ''';

      final events = LimitlessTcgService.parseTournamentList(html);

      expect(events, hasLength(1));
      expect(events.single.id, '584');
      expect(events.single.name, 'Regional Gdańsk');
      expect(events.single.date, '31 Oct 26');
      expect(events.single.country, 'PL');
      expect(events.single.players, 1739);
      expect(events.single.winner, 'Aarni Karjala');
      expect(events.single.format, 'standard');
    });

    test('extracts player placements from a tournament results table', () {
      const html = '''
        <html><body>
          <table>
            <tr><th>Place</th><th>Player</th><th>Country</th><th>Deck</th></tr>
            <tr>
              <td>1</td>
              <td><a href="/players/5163">Aarni Karjala</a></td>
              <td><img alt="FI" src="/flag.png"></td>
              <td><a href="/decks/322">Slowking</a></td>
            </tr>
          </table>
        </body></html>
      ''';

      final standings = LimitlessTcgService.parseStandings(html);

      expect(standings, hasLength(1));
      expect(standings.single.placing, 1);
      expect(standings.single.player, 'Aarni Karjala');
      expect(standings.single.country, 'FI');
      expect(standings.single.deck, 'Slowking');
    });
  });
}
