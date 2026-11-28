import 'dart:convert';
import 'dart:io';

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
  final Map<String, File?> _images = {};
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
      await _resolveLocalImages(cards);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  String _fileKey(String value) {
    var name = value.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    final hash = name.indexOf('__');
    if (hash >= 0) name = name.substring(0, hash);
    return _normalize(name);
  }

  Future<void> _resolveLocalImages(List<LimitlessDeckCard> cards) async {
    try {
      final sources = <String>[];
      final externalIndex = File('/sdcard/meuapp/dados_cartas.json');
      if (await externalIndex.exists()) {
        sources.add(await externalIndex.readAsString());
      }
      sources.add(await rootBundle.loadString('assets/data/dados_cartas.json'));

      final indexByKey = <String, Map<String, dynamic>>{};
      for (final raw in sources) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map || decoded['cards'] is! List) continue;
          for (final value in decoded['cards']) {
            if (value is! Map) continue;
            final item = Map<String, dynamic>.from(value);
            final id = item['collectionId']?.toString() ?? '';
            final slug = item['slug']?.toString() ?? '';
            final file = item['file']?.toString() ?? '';
            final key = '$id|${_fileKey(slug.isNotEmpty ? slug : file)}';
            if (id.isNotEmpty && key != '$id|') {
              indexByKey.putIfAbsent(key, () => item);
            }
          }
        } catch (_) {}
      }
      final index = indexByKey.values.toList(growable: false);
      if (index.isEmpty) return;

      final appRoot = Directory('/sdcard/meuapp');
      if (!await appRoot.exists()) return;
      Directory? base;
      await for (final entity in appRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final parts = entity.uri.pathSegments.where((part) => part.isNotEmpty);
        if (parts.isEmpty) continue;
        final folder = parts.last.toLowerCase();
        final normalized = folder
            .replaceAll('á', 'a').replaceAll('à', 'a')
            .replaceAll('ã', 'a').replaceAll('â', 'a')
            .replaceAll('é', 'e').replaceAll('ê', 'e')
            .replaceAll('í', 'i').replaceAll('ó', 'o')
            .replaceAll('ô', 'o').replaceAll('õ', 'o')
            .replaceAll('ú', 'u').replaceAll('ç', 'c');
        if (normalized == 'tcg fisico') {
          base = entity;
          break;
        }
      }
      if (base == null) return;

      final imageFiles = <String, File>{};
      await for (final collection in base.list(followLinks: false)) {
        if (collection is! Directory) continue;
        final parts = collection.uri.pathSegments.where((part) => part.isNotEmpty);
        if (parts.isEmpty) continue;
        final collectionId = parts.last.split('_').first;
        await for (final entity in collection.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final path = entity.path.toLowerCase();
          if (!const ['.jpg', '.jpeg', '.png', '.webp', '.gif']
              .any(path.endsWith)) continue;
          final key = _fileKey(entity.uri.pathSegments.last);
          if (key.isNotEmpty) {
            imageFiles.putIfAbsent('$collectionId|$key', () => entity);
          }
        }
      }

      final resolved = <String, File?>{};
      for (final deckCard in cards) {
        final wantedName = _normalize(deckCard.name);
        final wantedNumber = _normalize(deckCard.number.split('/').first);
        final candidates = index.where((item) {
          final nameMatches =
              _normalize(item['name']?.toString() ?? '') == wantedName;
          final indexedNumber = _normalize(
            (item['number']?.toString() ?? '').split('/').first,
          );
          final numberMatches =
              wantedNumber.isEmpty || indexedNumber == wantedNumber;
          return nameMatches && numberMatches;
        }).toList();

        File? foundImage;
        for (final item in candidates) {
          final collectionId = item['collectionId']?.toString() ?? '';
          final slug = item['slug']?.toString() ?? '';
          final file = item['file']?.toString() ?? '';
          final key = _fileKey(slug.isNotEmpty ? slug : file);
          foundImage = imageFiles['$collectionId|$key'];
          if (foundImage != null) break;
        }
        resolved['${deckCard.name}|${deckCard.number}'] = foundImage;
      }

      if (!mounted) return;
      setState(() => _images.addAll(resolved));
    } catch (error) {
      debugPrint('Falha ao localizar imagens locais da decklist: $error');
    }
  }

  void _showImage(File image) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: InteractiveViewer(
          child: Image.file(image, fit: BoxFit.contain),
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
                              final image = _images[
                                  '${deckCard.name}|${deckCard.number}'];
                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading: SizedBox(
                                  width: 54,
                                  child: image == null
                                      ? const Center(
                                          child: Icon(
                                            Icons.image_not_supported_outlined,
                                          ),
                                        )
                                      : GestureDetector(
                                          onTap: () => _showImage(image),
                                          child: Image.file(
                                            image,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                ),
                                title: Text(deckCard.name),
                                subtitle: Text(
                                  deckCard.number.isEmpty
                                      ? 'Imagem local não encontrada'
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
