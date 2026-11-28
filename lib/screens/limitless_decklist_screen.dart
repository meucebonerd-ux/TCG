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
  State<LimitlessDecklistScreen> createState() => _LimitlessDecklistScreenState();
}

class _LimitlessDecklistScreenState extends State<LimitlessDecklistScreen> {
  final LimitlessTcgService _service = LimitlessTcgService();
  List<LimitlessDeckCard> _cards = const [];
  final Map<String, File?> _images = {};
  bool _loading = true;
  String _error = '';
  int get _total => _cards.fold(0, (sum, card) => sum + card.quantity);

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
      if (mounted) setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _key(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  Future<void> _resolveLocalImages(List<LimitlessDeckCard> cards) async {
    try {
      String raw = await rootBundle.loadString('assets/data/dados_cartas.json');
      final externalIndex = File('/sdcard/meuapp/dados_cartas.json');
      if (await externalIndex.exists()) {
        raw = await externalIndex.readAsString();
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['cards'] is! List) return;
      final index = decoded['cards'].whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)).toList();

      final base = Directory('/sdcard/meuapp/TCG Fisico');
      if (!await base.exists()) return;
      final directories = <String, Directory>{};
      await for (final entity in base.list(followLinks: false)) {
        if (entity is Directory) {
          final name = entity.uri.pathSegments.where((v) => v.isNotEmpty).last;
          final id = name.split('_').first;
          directories[id] = entity;
        }
      }

      final resolved = <String, File?>{};
      for (final card in cards) {
        final candidates = index.where((item) {
          final nameMatches = _key(item['name']?.toString() ?? '') == _key(card.name);
          final indexedNumber = (item['number']?.toString() ?? '').split('/').first;
          final numberMatches = card.number.isEmpty ||
              _key(indexedNumber) == _key(card.number);
          final setMatches = card.collectionId.isEmpty ||
              !RegExp(r'^\\d+
          return nameMatches && numberMatches && setMatches;
        }).toList();

        File? image;
        for (final item in candidates) {
          final id = item['collectionId']?.toString() ?? '';
          final folder = directories[id];
          if (folder == null) continue;
          final fileName = (item['file'] ?? '').toString().split('/').last;
          if (fileName.isEmpty) continue;
          final direct = File('${folder.path}/$fileName');
          if (await direct.exists()) {
            image = direct;
            break;
          }
          await for (final entity in folder.list(recursive: true, followLinks: false)) {
            if (entity is File && entity.uri.pathSegments.last == fileName) {
              image = entity;
              break;
            }
          }
          if (image != null) break;
        }
        resolved['${card.name}|${card.number}'] = image;
      }
      if (mounted) setState(() => _images.addAll(resolved));
    } catch (_) {
      // A decklist remains usable as text when the local image index is absent.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Não foi possível carregar a decklist.\n$_error', textAlign: TextAlign.center),
                ))
              : _cards.isEmpty
                  ? const Center(child: Text('A decklist não está disponível publicamente.'))
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Expanded(child: Text('${_cards.length} cartas diferentes', style: Theme.of(context).textTheme.titleMedium)),
                          Text('$_total cartas'),
                        ]),
                      ),
                      Expanded(child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _cards.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final card = _cards[index];
                          final image = _images['${card.name}|${card.number}'];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            leading: SizedBox(
                              width: 54,
                              child: image != null
                                  ? GestureDetector(
                                      onTap: () => showDialog<void>(
                                        context: context,
                                        builder: (_) => Dialog(
                                          child: InteractiveViewer(
                                            child: Image.file(image, fit: BoxFit.contain),
                                          ),
                                        ),
                                      ),
                                      child: Image.file(image, fit: BoxFit.contain),
                                    )
                                  : const Center(child: Icon(Icons.image_not_supported_outlined)),
                            ),
                            title: Text(card.name),
                            subtitle: Text(card.number.isEmpty ? 'Imagem local não encontrada' : card.number),
                            trailing: Text('×${card.quantity}', style: Theme.of(context).textTheme.titleMedium),
                          );
                        },
                      )),
                    ]),
    );
  }
}
).hasMatch(card.collectionId) ||
              item['collectionId']?.toString() == card.collectionId;
          return nameMatches && numberMatches && setMatches;
        }).toList();

        File? image;
        for (final item in candidates) {
          final id = item['collectionId']?.toString() ?? '';
          final folder = directories[id];
          if (folder == null) continue;
          final fileName = (item['file'] ?? '').toString().split('/').last;
          if (fileName.isEmpty) continue;
          final direct = File('${folder.path}/$fileName');
          if (await direct.exists()) {
            image = direct;
            break;
          }
          await for (final entity in folder.list(recursive: true, followLinks: false)) {
            if (entity is File && entity.uri.pathSegments.last == fileName) {
              image = entity;
              break;
            }
          }
          if (image != null) break;
        }
        resolved['${card.name}|${card.number}'] = image;
      }
      if (mounted) setState(() => _images.addAll(resolved));
    } catch (_) {
      // A decklist remains usable as text when the local image index is absent.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Não foi possível carregar a decklist.\n$_error', textAlign: TextAlign.center),
                ))
              : _cards.isEmpty
                  ? const Center(child: Text('A decklist não está disponível publicamente.'))
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Expanded(child: Text('${_cards.length} cartas diferentes', style: Theme.of(context).textTheme.titleMedium)),
                          Text('$_total cartas'),
                        ]),
                      ),
                      Expanded(child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _cards.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final card = _cards[index];
                          final image = _images['${card.name}|${card.number}'];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            leading: SizedBox(
                              width: 54,
                              child: image != null
                                  ? GestureDetector(
                                      onTap: () => showDialog<void>(
                                        context: context,
                                        builder: (_) => Dialog(
                                          child: InteractiveViewer(
                                            child: Image.file(image, fit: BoxFit.contain),
                                          ),
                                        ),
                                      ),
                                      child: Image.file(image, fit: BoxFit.contain),
                                    )
                                  : const Center(child: Icon(Icons.image_not_supported_outlined)),
                            ),
                            title: Text(card.name),
                            subtitle: Text(card.number.isEmpty ? 'Imagem local não encontrada' : card.number),
                            trailing: Text('×${card.quantity}', style: Theme.of(context).textTheme.titleMedium),
                          );
                        },
                      )),
                    ]),
    );
  }
}
