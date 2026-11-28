import 'package:flutter/material.dart';

import '../services/limitless_tcg_service.dart';

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Classificação',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${_standings.length} jogadores'),
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
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: _standings.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final standing = _standings[index];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 17,
                                  child: Text(
                                    standing.placing?.toString() ?? '-',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Text(standing.player),
                                subtitle: Text([
                                  if (standing.country.isNotEmpty)
                                    standing.country,
                                  if (standing.deck.isNotEmpty)
                                    standing.deck,
                                ].join(' • ')),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
