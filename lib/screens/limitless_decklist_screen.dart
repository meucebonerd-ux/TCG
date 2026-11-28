import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/limitless_tcg_service.dart';

class LimitlessDecklistScreen extends StatefulWidget {
  final String title;
  final String decklistUrl;

  const LimitlessDecklistScreen({
    super.key,
    required this.title,
    required this.decklistUrl,
  });

  @override
  State<LimitlessDecklistScreen> createState() =>
      _LimitlessDecklistScreenState();
}

class _LimitlessDecklistScreenState extends State<LimitlessDecklistScreen> {
  final LimitlessTcgService _service = LimitlessTcgService();
  List<LimitlessDeckCard> _cards = const [];
  bool _loading = true;
  String _error = '';

  int get _total =>
      _cards.fold(0, (sum, card) => sum + card.quantity);

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
      final cards = await _service.fetchDecklist(widget.decklistUrl);
      if (!mounted) return;
      setState(() {
        _cards = cards;
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

  Future<void> _copyDeck() async {
    final buffer = StringBuffer();
    for (final card in _cards) {
      buffer.writeln('${card.quantity} ${card.name} ${card.collectionId} ${card.number}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deck copiado para a área de transferência.')),
    );
  }

  void _showImage(String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 180, child: Center(child: Icon(Icons.broken_image_outlined))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Copiar deck',
            onPressed: _cards.isEmpty ? null : _copyDeck,
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Não foi possível carregar a decklist.\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _cards.isEmpty
                  ? const Center(
                      child: Text(
                        'A decklist não está disponível publicamente.',
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_cards.length} cartas diferentes',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Text('$_total cartas'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: _cards.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final deckCard = _cards[index];
                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading: SizedBox(
                                  width: 54,
                                  height: 76,
                                  child: deckCard.imageUrl.isEmpty
                                      ? const Center(child: Icon(Icons.image_not_supported_outlined))
                                      : GestureDetector(
                                          onTap: () => _showImage(deckCard.imageUrl),
                                          child: Image.network(
                                            deckCard.imageUrl,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                                          ),
                                        ),
                                ),
                                title: Text(deckCard.name),
                                subtitle: Text(
                                  deckCard.number.isEmpty
                                      ? 'Imagem indisponível no Limitless'
                                      : deckCard.number,
                                ),
                                trailing: Text(
                                  '×${deckCard.quantity}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
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
