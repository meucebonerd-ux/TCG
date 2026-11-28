import 'package:flutter/material.dart';

import '../services/limitless_tcg_service.dart';
import 'limitless_decklist_screen.dart';

class LimitlessTournamentsScreen extends StatefulWidget {
  const LimitlessTournamentsScreen({super.key});

  @override
  State<LimitlessTournamentsScreen> createState() =>
      _LimitlessTournamentsScreenState();
}

class _LimitlessTournamentsScreenState
    extends State<LimitlessTournamentsScreen> {
  final LimitlessTcgService _service = LimitlessTcgService();
  final TextEditingController _searchController = TextEditingController();
  List<LimitlessTournament> _tournaments = const [];
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = _tournaments.isEmpty;
        _refreshing = _tournaments.isNotEmpty;
        _error = '';
      });
    }
    try {
      final events = await _service.fetchTournaments(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _tournaments = events;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  bool _isMajor(String name) {
    final value = name.toLowerCase();
    return value.contains('regional') ||
        value.contains('international') ||
        value.contains('world championship') ||
        value.contains('special event') ||
        value.contains('city league') ||
        value.contains('champions league');
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = _tournaments.where((event) {
      if (!_isMajor(event.name)) return false;
      if (query.isEmpty) return true;
      return event.name.toLowerCase().contains(query) ||
          event.country.toLowerCase().contains(query) ||
          event.winner.toLowerCase().contains(query) ||
          event.date.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Torneios presenciais'),
        actions: [
          IconButton(
            tooltip: 'Atualizar dados',
            onPressed: _refreshing ? null : () => _load(forceRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar torneio, país ou vencedor',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_error.isNotEmpty)
                  MaterialBanner(
                    content: Text(
                      _tournaments.isEmpty
                          ? 'Não foi possível consultar o Limitless. $_error'
                          : 'Não foi possível atualizar. Exibindo dados salvos. $_error',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => _load(forceRefresh: true),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                if (_refreshing)
                  const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${visible.length} torneios encontrados',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const Text(
                        'Fonte: Limitless TCG',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            _tournaments.isEmpty
                                ? 'Nenhum torneio disponível.'
                                : 'Nenhum torneio presencial corresponde à busca.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(forceRefresh: true),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final event = visible[index];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      event.country.isEmpty
                                          ? 'TCG'
                                          : event.country.toUpperCase(),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                  title: Text(
                                    event.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    [
                                      event.date,
                                      if (event.players != null)
                                        '${event.players} jogadores',
                                      if (event.winner.isNotEmpty)
                                        'Vencedor: ${event.winner}',
                                    ].join(' • '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing:
                                      const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          LimitlessTournamentDetailScreen(
                                        tournament: event,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class LimitlessTournamentDetailScreen extends StatefulWidget {
  final LimitlessTournament tournament;

  const LimitlessTournamentDetailScreen({
    super.key,
    required this.tournament,
  });

  @override
  State<LimitlessTournamentDetailScreen> createState() =>
      _LimitlessTournamentDetailScreenState();
}

class _LimitlessTournamentDetailScreenState
    extends State<LimitlessTournamentDetailScreen> {
  final LimitlessTcgService _service = LimitlessTcgService();
  final TextEditingController _participantSearch = TextEditingController();
  String _deckFilter = 'Todos os decks';
  List<LimitlessStanding> _standings = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _participantSearch.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await _service.fetchStandings(widget.tournament.id);
      if (!mounted) return;
      setState(() {
        _standings = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.tournament;
    final decks = _standings
        .map((standing) => standing.deck.trim())
        .where((deck) => deck.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final participantQuery = _participantSearch.text.trim().toLowerCase();
    final visibleStandings = _standings.where((standing) {
      final participantMatches = participantQuery.isEmpty ||
          standing.player.toLowerCase().contains(participantQuery) ||
          standing.country.toLowerCase().contains(participantQuery);
      final deckMatches = _deckFilter == 'Todos os decks' ||
          standing.deck == _deckFilter;
      return participantMatches && deckMatches;
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(event.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(event.date),
                  if (event.players != null)
                    Text('${event.players} jogadores'),
                  if (event.winner.isNotEmpty)
                    Text('Vencedor: ${event.winner}'),
                  const SizedBox(height: 8),
                  Text(
                    'Dados públicos do Limitless TCG',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _participantSearch,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Filtrar participantes',
                hintText: 'Nome do jogador ou país',
                prefixIcon: const Icon(Icons.person_search),
                suffixIcon: _participantSearch.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar participante',
                        onPressed: () {
                          _participantSearch.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: DropdownButtonFormField<String>(
              value: _deckFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Filtrar decks',
                prefixIcon: Icon(Icons.style),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: ['Todos os decks', ...decks]
                  .map((deck) => DropdownMenuItem(
                        value: deck,
                        child: Text(deck, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (value) => setState(() {
                _deckFilter = value ?? 'Todos os decks';
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Participantes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${visibleStandings.length} de ${_standings.length}'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Não foi possível carregar a classificação.\n$_error',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _standings.isEmpty
                        ? const Center(
                            child: Text(
                              'A classificação não está disponível nesta página.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : visibleStandings.isEmpty
                            ? const Center(
                                child: Text('Nenhum participante corresponde aos filtros.'),
                              )
                            : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: visibleStandings.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final standing = visibleStandings[index];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 17,
                                  child: Text(
                                    standing.placing?.toString() ?? '-',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    if (standing.deckImageUrl.isNotEmpty) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.network(
                                          standing.deckImageUrl,
                                          width: 34,
                                          height: 46,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => const SizedBox(
                                            width: 34,
                                            height: 46,
                                            child: Icon(Icons.style_outlined, size: 20),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(child: Text(standing.player)),
                                  ],
                                ),
                                subtitle: Text([
                                  if (standing.country.isNotEmpty)
                                    standing.country,
                                  if (standing.deck.isNotEmpty)
                                    standing.deck,
                                ].join(' • ')),
                                trailing: standing.decklistUrl.isNotEmpty
                                    ? const Icon(Icons.chevron_right)
                                    : null,
                                onTap: standing.decklistUrl.isEmpty
                                    ? null
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LimitlessDecklistScreen(
                                              title: '${standing.player} • ${standing.deck}',
                                              decklistUrl: standing.decklistUrl,
                                            ),
                                          ),
                                        ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
