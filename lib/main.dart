import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

const String raizColecoes = '/sdcard/meuapp/tcg físico';
const Set<String> extensoesImagem = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

final ValueNotifier<bool> modoEscuroGlobal = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferencias = await SharedPreferences.getInstance();
  modoEscuroGlobal.value = preferencias.getBool('modo_escuro') ?? true;
  runApp(const PokemonTcgApp());
}

class PokemonTcgApp extends StatelessWidget {
  const PokemonTcgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: modoEscuroGlobal,
      builder: (context, escuro, _) => MaterialApp(
        title: 'Pokemon TCG Manager',
        themeMode: escuro ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const ColecoesScreen(),
      ),
    );
  }
}

class Carta {
  final String nome;
  final File arquivo;
  final Map<String, dynamic>? dados;
  final String collectionName;
  final String collectionId;

  const Carta({required this.nome, required this.arquivo, this.dados, this.collectionName = '', this.collectionId = ''});
}

class Colecao {
  final String nome;
  final Directory pasta;
  final List<Carta> cartas;
  final File? logo;
  final String? ano;
  final int totalCartas;

  const Colecao({required this.nome, required this.pasta, required this.cartas, this.logo, this.ano, this.totalCartas = 0});
}

class ColecoesScreen extends StatefulWidget {
  const ColecoesScreen({super.key});

  @override
  State<ColecoesScreen> createState() => _ColecoesScreenState();
}

class _ColecoesScreenState extends State<ColecoesScreen> {
  List<Colecao> colecoes = [];
  Colecao? colecaoSelecionada;
  bool carregando = true;
  bool carregandoColecao = false;
  String erroMsg = '';
  String filtroTipo = 'Todos';
  String filtroRaridade = 'Todas';
  String filtroCategoria = 'Todas';
  final ScrollController _catalogoScrollController = ScrollController();
  double _catalogoScrollOffset = 0;

  void _restaurarPosicaoCatalogo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_catalogoScrollController.hasClients) return;
      final limite = _catalogoScrollController.position.maxScrollExtent;
      _catalogoScrollController.jumpTo(_catalogoScrollOffset.clamp(0.0, limite).toDouble());
    });
  }

  @override
  void initState() {
    super.initState();
    carregarColecoes();
  }

  @override
  void dispose() {
    _catalogoScrollController.dispose();
    super.dispose();
  }

  Future<bool> garantirPermissao() async {
    if (!Platform.isAndroid) return true;

    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permissão de arquivos necessária'),
          content: const Text(
            'Para listar as coleções e abrir as imagens, permita que o '
            'Pokemon TCG Manager gerencie todos os arquivos nas configurações '
            'do Android. Depois volte ao aplicativo e atualize a tela.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              child: const Text('Abrir configurações'),
            ),
          ],
        ),
      );
    }
    return false;
  }

  Map<String, Map<String, dynamic>>? _indiceCartasCache;
  final Map<String, List<Carta>> _cartasPorColecao = {};
  List<Carta>? _cartasBuscaGlobalCache;

  Future<int> _contarImagensDaColecao(Directory pasta) async {
    var total = 0;
    await for (final item in pasta.list(recursive: true, followLinks: false)) {
      if (item is! File) continue;
      final nome = item.path.toLowerCase();
      if (extensoesImagem.any((ext) => nome.endsWith(ext))) total++;
    }
    return total;
  }
  Future<void> carregarColecoes() async {
    setState(() { carregando = true; erroMsg = ''; });
    try {
      final permitido = await garantirPermissao();
      if (!permitido) {
        if (mounted) setState(() { erroMsg = 'Permissão de acesso aos arquivos não concedida.'; carregando = false; });
        return;
      }
      final pastaBase = Directory('/sdcard/meuapp');
      if (!await pastaBase.exists()) throw Exception('Pasta /sdcard/meuapp não encontrada.');
      String normalizarNome(String valor) => valor.toLowerCase().replaceAll('á','a').replaceAll('à','a').replaceAll('ã','a').replaceAll('â','a').replaceAll('é','e').replaceAll('ê','e').replaceAll('í','i').replaceAll('ó','o').replaceAll('ô','o').replaceAll('õ','o').replaceAll('ú','u').replaceAll('ç','c').trim();
      Directory? raiz;
      await for (final item in pastaBase.list(followLinks: false)) {
        if (item is Directory && normalizarNome(item.path.split(Platform.pathSeparator).last) == 'tcg fisico') { raiz = item; break; }
      }
      if (raiz == null) throw Exception('Pasta "tcg fisico" não encontrada dentro de /sdcard/meuapp.');
      final pastaLogos = Directory('/sdcard/meuapp/logos');
      final arquivosLogo = <String, String>{};
      final ordemCatalogo = <String, int>{};
      final anosCatalogo = <String, String>{};
      final arquivoCatalogo = File('${pastaLogos.path}/catalogo.json');
      if (await arquivoCatalogo.exists()) {
        final dados = jsonDecode(await arquivoCatalogo.readAsString());
        if (dados is List) for (var i = 0; i < dados.length; i++) {
          final item = dados[i];
          if (item is Map) {
            final id = item['id']?.toString(); final nomeArquivo = item['arquivo']?.toString();
            if (id != null && id.isNotEmpty && nomeArquivo != null) {
              arquivosLogo[id] = nomeArquivo; ordemCatalogo[id] = i;
              final anoRaw = item['ano'] ?? item['year'] ?? item['releaseYear'] ?? item['releaseDate'];
              final match = RegExp(r'(?:19|20)\d{2}').firstMatch(anoRaw?.toString() ?? '');
              if (match != null) anosCatalogo[id] = match.group(0)!;
            }
          }
        }
      }
      String idDaPasta(Directory pasta) { final nome = _nomePasta(pasta); final p = nome.indexOf('_'); return p > 0 ? nome.substring(0, p) : nome; }
      final pastas = <Directory>[];
      await for (final item in raiz.list(followLinks: false)) { if (item is Directory) pastas.add(item); }
      pastas.sort((x, y) { final a = ordemCatalogo[idDaPasta(x)] ?? 999999; final b = ordemCatalogo[idDaPasta(y)] ?? 999999; return a != b ? a.compareTo(b) : _nomePasta(x).toLowerCase().compareTo(_nomePasta(y).toLowerCase()); });
      final indice = await _carregarIndiceCartas();
      final quantidades = <String, int>{};
      for (final chave in indice.keys) { final p = chave.indexOf('|'); if (p > 0) { final id = chave.substring(0, p); quantidades[id] = (quantidades[id] ?? 0) + 1; } }
      final resultado = <Colecao>[];
      for (final pasta in pastas) {
        final id = idDaPasta(pasta);
        final logoNome = arquivosLogo[id];
        final logo = logoNome == null ? null : File(pastaLogos.path + '/' + logoNome);
        var totalIndice = quantidades[id] ?? 0;
        // Quando o JSON não tem os metadados de uma coleção, conta as imagens locais.
        if (totalIndice == 0) totalIndice = await _contarImagensDaColecao(pasta);
        resultado.add(Colecao(
          nome: _nomePasta(pasta),
          pasta: pasta,
          cartas: const <Carta>[],
          logo: logo != null && await logo.exists() ? logo : null,
          ano: anosCatalogo[id] ?? RegExp(r'(?:19|20)\d{2}').firstMatch(_nomePasta(pasta))?.group(0),
          totalCartas: totalIndice,
        ));
      }
      if (!mounted) return;
      setState(() { colecoes = resultado; colecaoSelecionada = null; _cartasPorColecao.clear(); _cartasBuscaGlobalCache = null; _indiceCartasCache = null; carregando = false; });
    } catch (e) { if (mounted) setState(() { erroMsg = 'Erro ao carregar coleções: $e'; carregando = false; }); }
  }

  Future<Map<String, Map<String, dynamic>>> _carregarIndiceCartas() async {
    if (_indiceCartasCache != null) return _indiceCartasCache!;

    // O crawler original grava o índice completo neste caminho compartilhado.
    // O asset embarcado continua como fallback e complemento.
    final fontes = <String>[];
    final arquivoExterno = File('/sdcard/meuapp/dados_cartas.json');
    if (await arquivoExterno.exists()) {
      fontes.add(await arquivoExterno.readAsString());
    }
    fontes.add(await rootBundle.loadString('assets/data/dados_cartas.json'));

    final resultado = <String, Map<String, dynamic>>{};
    for (final conteudo in fontes) {
      try {
        final json = jsonDecode(conteudo);
        if (json is! Map || json['cards'] is! List) continue;
        for (final item in json['cards']) {
          if (item is! Map) continue;
          final dados = Map<String, dynamic>.from(item);
          final id = dados['collectionId']?.toString();
          final arquivo = _arquivoDaCarta(dados);
          final slug = _texto(dados, 'slug').trim();
          final nome = _texto(dados, 'name').trim();
          final identificador = slug.isNotEmpty ? slug : (arquivo.isNotEmpty ? arquivo : nome);
          if (id == null || id.isEmpty || identificador.isEmpty) continue;
          final chave = '$id|${_normalizarChave(identificador)}';
          // O JSON externo tem prioridade; o asset preenche apenas ausências.
          resultado.putIfAbsent(chave, () => dados);
        }
      } catch (e) {
        debugPrint('Falha ao ler uma fonte do índice de cartas: $e');
      }
    }
    _indiceCartasCache = resultado;
    debugPrint('Índice de cartas carregado: ${resultado.length} registros.');
    return resultado;
  }

  String _slugDoArquivoLocal(String nomeArquivo) {
    final ponto = nomeArquivo.lastIndexOf('.');
    final semExtensao = ponto > 0 ? nomeArquivo.substring(0, ponto) : nomeArquivo;
    final separadorHash = semExtensao.indexOf('__');
    return separadorHash >= 0 ? semExtensao.substring(0, separadorHash) : semExtensao;
  }

  String _nomeLegivelDoSlug(String slug) => slug
      .replaceFirst(RegExp(r'-\d{1,4}-\d{1,4}$'), '')
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .trim();

  Future<List<Carta>> _carregarCartasDaColecao(Colecao colecao) async {
    final id = colecao.nome.split('_').first;
    if (_cartasPorColecao.containsKey(id)) return _cartasPorColecao[id]!;

    final indice = await _carregarIndiceCartas();
    final imagensPorNome = <String, File>{};
    final imagensPorSlug = <String, File>{};
    await for (final item in colecao.pasta.list(recursive: true, followLinks: false)) {
      if (item is! File) continue;
      final nomeArquivo = item.uri.pathSegments.isNotEmpty ? item.uri.pathSegments.last : item.path.split(Platform.pathSeparator).last;
      final ponto = nomeArquivo.lastIndexOf('.');
      final ext = ponto >= 0 ? nomeArquivo.substring(ponto).toLowerCase() : '';
      if (!extensoesImagem.contains(ext)) continue;
      imagensPorNome[_normalizarChave(nomeArquivo)] = item;
      final slugLocal = _slugDoArquivoLocal(nomeArquivo);
      if (slugLocal.isNotEmpty) imagensPorSlug[_normalizarChave(slugLocal)] = item;
    }

    final cartas = <Carta>[];
    final slugsIndexados = <String>{};
    for (final entry in indice.entries) {
      if (!entry.key.startsWith('$id|')) continue;
      final dados = entry.value;
      if (dados['collectionId']?.toString() != id) continue;
      final nomeArquivo = _arquivoDaCarta(dados);
      final slug = _texto(dados, 'slug').trim();
      final chave = _normalizarChave(slug.isNotEmpty ? slug : nomeArquivo);
      if (chave.isNotEmpty) slugsIndexados.add(chave);
      final imagem = (nomeArquivo.isEmpty ? null : imagensPorNome[_normalizarChave(nomeArquivo)]) ??
          (slug.isEmpty ? null : imagensPorSlug[_normalizarChave(slug)]) ??
          (nomeArquivo.isEmpty ? null : imagensPorSlug[_normalizarChave(_slugDoArquivoLocal(nomeArquivo))]);
      final nomeDados = _texto(dados, 'name').trim();
      final nomeSemExtensao = nomeArquivo.contains('.') ? nomeArquivo.substring(0, nomeArquivo.lastIndexOf('.')) : nomeArquivo;
      cartas.add(Carta(
        nome: nomeDados.isNotEmpty ? nomeDados : (slug.isNotEmpty ? _nomeLegivelDoSlug(slug) : nomeSemExtensao),
        arquivo: imagem ?? File('/__tcg_missing_image__/' + (nomeArquivo.isEmpty ? slug : nomeArquivo)),
        dados: dados,
        collectionName: _texto(dados, 'collectionName').isNotEmpty ? _texto(dados, 'collectionName') : colecao.nome.replaceFirst(RegExp(r'^\d+_'), '').replaceAll('_', ' '),
        collectionId: id,
      ));
    }

    // Cada arquivo slug__hash.ext passa a ser reconhecido sem cadastro manual.
    for (final entry in imagensPorSlug.entries) {
      if (slugsIndexados.contains(entry.key)) continue;
      final arquivo = entry.value;
      final nomeArquivo = arquivo.uri.pathSegments.last;
      final slug = _slugDoArquivoLocal(nomeArquivo);
      if (slug.isEmpty) continue;
      final numeroMatch = RegExp(r'-(\d{1,4})-(\d{1,4})$').firstMatch(slug);
      final numero = numeroMatch == null ? null : int.tryParse(numeroMatch.group(1)!);
      final total = numeroMatch == null ? null : int.tryParse(numeroMatch.group(2)!);
      final nomeColecao = colecao.nome.replaceFirst(RegExp(r'^\d+_'), '').replaceAll('_', ' ');
      final dados = <String, dynamic>{
        'collectionId': id, 'collectionName': nomeColecao, 'slug': slug, 'file': nomeArquivo,
        'name': _nomeLegivelDoSlug(slug),
        'number': numero == null ? '' : numero.toString().padLeft(3, '0') + '/' + (total?.toString() ?? ''),
        'numberSort': numero, 'supertype': 'Unknown', 'types': <String>[], 'needsReview': true,
      };
      cartas.add(Carta(
        nome: _nomeLegivelDoSlug(slug).isEmpty ? slug : _nomeLegivelDoSlug(slug),
        arquivo: arquivo, dados: dados, collectionName: nomeColecao, collectionId: id,
      ));
    }

    _ordenarCartas(cartas);
    _cartasPorColecao[id] = cartas;
    return cartas;
  }

  Future<void> _abrirColecao(Colecao colecao) async {
    if (carregandoColecao) return;
    setState(() => carregandoColecao = true);
    try {
      final cartas = await _carregarCartasDaColecao(colecao);
      if (!mounted) return;
      setState(() { colecaoSelecionada = Colecao(nome: colecao.nome, pasta: colecao.pasta, cartas: cartas, logo: colecao.logo, ano: colecao.ano, totalCartas: colecao.totalCartas); carregandoColecao = false; });
    } catch (e) { if (mounted) setState(() { carregandoColecao = false; erroMsg = 'Erro ao abrir coleção: $e'; }); }
  }
  String _arquivoDaCarta(Map<String, dynamic>? dados) {
    final direto = _texto(dados, 'file').trim();
    if (direto.isNotEmpty) return direto.replaceAll('\\\\', '/').split('/').last;
    final arquivos = dados?['files'];
    if (arquivos is List) {
      for (final item in arquivos) {
        final caminho = item?.toString().trim() ?? '';
        if (caminho.isNotEmpty) return caminho.replaceAll('\\\\', '/').split('/').last;
      }
    }
    return '';
  }

  String _normalizarChave(String valor) => valor
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  int _ordemTipoPokemon(Carta carta) {
    const ordem = <String, int>{
      'grass': 0, 'fire': 1, 'water': 2, 'lightning': 3,
      'psychic': 4, 'fighting': 5, 'darkness': 6, 'metal': 7,
      'fairy': 8, 'dragon': 9, 'colorless': 10,
    };
    final tipos = _tiposDaCarta(carta);
    if (tipos.isEmpty) return 99;
    return ordem[_tipoCanonico(tipos.first)] ?? 99;
  }

  String _textoCampos(Map<String, dynamic>? dados, List<String> chaves) {
    if (dados == null) return '';
    final partes = <String>[];
    for (final chave in chaves) {
      final valor = dados[chave];
      if (valor is List) {
        partes.addAll(valor.map((e) => e.toString()));
      } else if (valor != null) {
        partes.add(valor.toString());
      }
    }
    return _normalizarChave(partes.join(' '));
  }

  int _ordemTreinador(Carta carta) {
    final dados = carta.dados;
    final subtipo = _textoCampos(dados, [
      'trainerSubtype', 'trainerType', 'subtype', 'subtypes',
      'cardType', 'category',
    ]);
    if (subtipo.contains('stadium') || subtipo.contains('estadio')) return 1;
    if (subtipo.contains('supporter') || subtipo.contains('apoiador')) return 2;
    if (subtipo.contains('pokemon tool') ||
        subtipo.contains('tool') ||
        subtipo.contains('ferramenta')) return 3;
    if (subtipo.contains('item') || subtipo.contains('item')) return 0;
    // Em índices antigos, cartas de Treinador sem subtipo explícito
    // são tratadas como Itens para não misturá-las aos demais grupos.
    return 0;
  }

  bool _ehEnergiaBasica(Carta carta) {
    final dados = carta.dados;
    final categoria = _textoCampos(dados, ['energyCategory', 'energyType', 'subtypes']);
    final nome = _normalizarChave(carta.nome);
    if (categoria.contains('special') || categoria.contains('especial')) return false;
    if (categoria.contains('basic') || categoria.contains('basica')) return true;
    if (nome.contains('special energy') || nome.contains('energia especial')) return false;
    if (nome.contains('basic energy') || nome.contains('energia basica')) return true;
    // Nos metadados antigos, energyType sozinho identifica Energia Básica.
    if (_texto(dados, 'energyType').trim().isNotEmpty) return true;
    return false;
  }

  int _ordemEnergia(Carta carta) {
    if (!_ehEnergiaBasica(carta)) return 100;
    final energia = _texto(carta.dados, 'energyType').trim();
    final nome = _normalizarChave(carta.nome);
    final tipo = _tipoCanonico(energia.isNotEmpty ? energia : nome
        .replaceAll(' basic energy', '')
        .replaceAll(' energy', '')
        .replaceAll(' energia basica', '')
        .replaceAll(' energia', ''));
    const ordem = <String, int>{
      'grass': 0, 'fire': 1, 'water': 2, 'lightning': 3,
      'psychic': 4, 'fighting': 5, 'darkness': 6, 'metal': 7,
      'fairy': 8, 'dragon': 9, 'colorless': 10,
    };
    return ordem[tipo] ?? 99;
  }

  String _chaveAlfabetica(Carta carta) {
    final nome = _normalizarChave(carta.nome);
    return nome;
  }

  void _ordenarCartas(List<Carta> cartas) {
    int grupo(Carta carta) {
      final categoria = _categoriaDaCarta(carta);
      if (categoria == 'Pokémon') return 0;
      if (categoria == 'Treinador / não identificado') return 1;
      if (categoria == 'Energia') return 2;
      return 3;
    }

    cartas.sort((a, b) {
      final ga = grupo(a), gb = grupo(b);
      if (ga != gb) return ga.compareTo(gb);

      if (ga == 0) {
        final tipo = _ordemTipoPokemon(a).compareTo(_ordemTipoPokemon(b));
        if (tipo != 0) return tipo;
        final nome = _chaveAlfabetica(a).compareTo(_chaveAlfabetica(b));
        if (nome != 0) return nome;
      } else if (ga == 1) {
        final sub = _ordemTreinador(a).compareTo(_ordemTreinador(b));
        if (sub != 0) return sub;
        final nome = _chaveAlfabetica(a).compareTo(_chaveAlfabetica(b));
        if (nome != 0) return nome;
      } else if (ga == 2) {
        final basicaA = _ehEnergiaBasica(a) ? 0 : 1;
        final basicaB = _ehEnergiaBasica(b) ? 0 : 1;
        if (basicaA != basicaB) return basicaA.compareTo(basicaB);
        if (basicaA == 0) {
          final tipo = _ordemEnergia(a).compareTo(_ordemEnergia(b));
          if (tipo != 0) return tipo;
        }
        final nome = _chaveAlfabetica(a).compareTo(_chaveAlfabetica(b));
        if (nome != 0) return nome;
      }

      final slugA = _texto(a.dados, 'slug');
      final slugB = _texto(b.dados, 'slug');
      return slugA.compareTo(slugB);
    });
  }
  String _nomeExibicao(Colecao item) =>
      item.nome.replaceFirst(RegExp(r'^\\d+_'), '').replaceAll('_', ' ');

  Future<void> _abrirBuscaColecao() async {
    if (colecoes.isEmpty) return;
    final controller = TextEditingController();
    final selecionada = await showModalBottomSheet<Colecao>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, atualizarBusca) {
          final termo = controller.text.trim().toLowerCase();
          final resultados = colecoes.where((item) {
            final id = item.nome.split('_').first;
            return termo.isEmpty || _nomeExibicao(item).toLowerCase().contains(termo) ||
                id.contains(termo) || (item.ano ?? '').contains(termo) ||
                item.nome.toLowerCase().contains(termo);
          }).toList();
          return SafeArea(child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
            child: SizedBox(height: MediaQuery.of(sheetContext).size.height * 0.72,
              child: Column(children: [
                const Align(alignment: Alignment.centerLeft, child: Text('Buscar coleção', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                const SizedBox(height: 12),
                TextField(controller: controller, autofocus: true, onChanged: (_) => atualizarBusca(() {}),
                  decoration: InputDecoration(hintText: 'Nome, ID ou ano (ex.: 151, 2023)', prefixIcon: const Icon(Icons.search),
                    suffixIcon: controller.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { controller.clear(); atualizarBusca(() {}); }),
                    border: const OutlineInputBorder())),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: Text('${resultados.length} coleções encontradas', style: Theme.of(context).textTheme.bodySmall)),
                const SizedBox(height: 4),
                Expanded(child: resultados.isEmpty ? const Center(child: Text('Nenhuma coleção corresponde à busca.')) :
                  ListView.separated(itemCount: resultados.length, separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = resultados[index]; final id = item.nome.split('_').first;
                      return ListTile(leading: SizedBox(width: 52, height: 52, child: item.logo != null ? Image.file(item.logo!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.collections_outlined)) : const Icon(Icons.collections_outlined)),
                        title: Text(_nomeExibicao(item), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('ID $id${item.ano == null ? '' : ' • ${item.ano}'} • ${item.cartas.length} cartas'),
                        onTap: () => Navigator.pop(sheetContext, item));
                    })),
              ]),
            ),
          ));
        },
      ),
    );
    controller.dispose();
    if (selecionada != null && mounted) {
      _catalogoScrollOffset = _catalogoScrollController.hasClients
          ? _catalogoScrollController.offset
          : _catalogoScrollOffset;
      setState(() => colecaoSelecionada = selecionada);
    }
  }


  String _texto(Map<String, dynamic>? dados, String chave) => (dados?[chave] ?? '').toString();

  List<String> _tiposDaCarta(Carta carta) {
    // O índice antigo juntou tipo do Pokémon com custos de energia dos ataques.
    // O primeiro item corresponde ao tipo principal; os demais não são tipos da carta.
    final value = carta.dados?['types'];
    if (value is List && value.isNotEmpty) {
      final principal = value.first.toString().trim();
      return principal.isEmpty ? <String>[] : <String>[principal];
    }
    final energy = _texto(carta.dados, 'energyType').trim();
    return energy.isEmpty ? <String>[] : <String>[energy];
  }

  String _tipoCanonico(String valor) {
    final normalizado = _normalizarChave(valor);
    const aliases = {
      'grama': 'grass', 'planta': 'grass',
      'fogo': 'fire', 'agua': 'water',
      'eletrico': 'lightning', 'raios': 'lightning',
      'psiquico': 'psychic', 'lutador': 'fighting',
      'sombrio': 'darkness', 'noturno': 'darkness',
      'metalico': 'metal', 'metal': 'metal',
      'fada': 'fairy', 'dragao': 'dragon', 'incolor': 'colorless',
    };
    return aliases[normalizado] ?? normalizado;
  }

  String _categoriaDaCarta(Carta carta) {
    final dados = carta.dados ?? const <String, dynamic>{};
    final supertype = _normalizarChave(_texto(dados, 'supertype'));
    final energyType = _texto(dados, 'energyType').trim();
    final energyCategory = _texto(dados, 'energyCategory').trim();
    final nome = _normalizarChave(
      _texto(dados, 'name').trim().isNotEmpty ? _texto(dados, 'name') : carta.nome,
    );
    final types = dados['types'];
    final temTipo = types is List &&
        types.any((item) => item.toString().trim().isNotEmpty);

    // Alguns índices antigos marcaram todas as cartas como Trainer/Stadium.
    // Neles, Pokémon e Energias ainda conservam o tipo impresso; use esses
    // sinais para corrigir a categoria sem reclassificar Trainers sem tipo.
    final pareceEnergia = energyType.isNotEmpty || energyCategory.isNotEmpty ||
        nome.endsWith(' energy') || nome.endsWith(' energia');
    if (supertype == 'energy' || supertype == 'energia' || pareceEnergia) {
      return 'Energia';
    }
    if (supertype == 'pokemon' || supertype == 'pokémon') return 'Pokémon';
    if ((supertype == 'trainer' || supertype == 'treinador') && temTipo) {
      return 'Pokémon';
    }
    if (supertype == 'trainer' || supertype == 'treinador') {
      return 'Treinador / não identificado';
    }

    final stage = _normalizarChave(_texto(dados, 'stage'));
    const estagiosPokemon = {
      'basic', 'stage 1', 'stage 2', 'vmax', 'vstar',
      'level up', 'break', 'legend', 'v union', 'restored',
    };
    final temEvolucaoPokemon = _texto(dados, 'evolvesFrom').trim().isNotEmpty;
    if (temTipo || estagiosPokemon.contains(stage) || temEvolucaoPokemon) {
      return 'Pokémon';
    }
    return 'Treinador / não identificado';
  }
  String _raridadeDaCarta(Carta carta) {
    final value = carta.dados?['rarity'] ?? carta.dados?['rarities'];
    if (value is List) return value.map((e) => e.toString()).join(', ');
    return (value ?? '').toString();
  }

  bool _cartaPassaFiltros(Carta carta) {
    final tipoOk = filtroTipo == 'Todos' || _tiposDaCarta(carta).any((t) => _tipoCanonico(t) == _tipoCanonico(filtroTipo));
    final raridade = _raridadeDaCarta(carta);
    final raridadeOk = filtroRaridade == 'Todas' || (raridade.isNotEmpty && raridade == filtroRaridade);
    final categoriaOk = filtroCategoria == 'Todas' || _categoriaDaCarta(carta) == filtroCategoria;
    return tipoOk && raridadeOk && categoriaOk;
  }

  Future<void> _abrirFiltrosColecao() async {
    final cartas = colecaoSelecionada?.cartas ?? <Carta>[];
    final tipos = <String>{};
    final raridades = <String>{};
    final categorias = <String>{};
    for (final carta in cartas) {
      tipos.addAll(_tiposDaCarta(carta));
      final raridade = _raridadeDaCarta(carta);
      if (raridade.isNotEmpty) raridades.add(raridade);
      categorias.add(_categoriaDaCarta(carta));
    }
    final tiposOrdenados = tipos.toList()..sort();
    final raridadesOrdenadas = raridades.toList()..sort();
    final categoriasOrdenadas = categorias.toList()..sort();
    var tipo = tipos.contains(filtroTipo) ? filtroTipo : 'Todos';
    var raridade = raridades.contains(filtroRaridade) ? filtroRaridade : 'Todas';
    var categoria = categorias.contains(filtroCategoria) ? filtroCategoria : 'Todas';
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, atualizar) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filtros da coleção', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tipo, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: ['Todos', ...tiposOrdenados].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => atualizar(() => tipo = v ?? 'Todos'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: raridade, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Raridade', border: OutlineInputBorder()),
                items: ['Todas', ...raridadesOrdenadas].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: raridades.isEmpty ? null : (v) => atualizar(() => raridade = v ?? 'Todas'),
              ),
              if (raridades.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 4), child: Text('O índice atual não possui dados de raridade; esse filtro será ativado quando o campo estiver disponível.', style: TextStyle(fontSize: 12))),
              const SizedBox(height: 12),
              if (categorias.length == 1 && categorias.first == 'Trainer • Stadium')
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('A categoria do índice está inconsistente: todas as cartas aparecem como Trainer • Stadium. O filtro será confiável após corrigirmos esses metadados.', style: TextStyle(fontSize: 12)),
                ),
              DropdownButtonFormField<String>(
                value: categoria, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                items: ['Todas', ...categoriasOrdenadas].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => atualizar(() => categoria = v ?? 'Todas'),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () {
                  setState(() { filtroTipo = 'Todos'; filtroRaridade = 'Todas'; filtroCategoria = 'Todas'; });
                  Navigator.pop(sheetContext);
                }, child: const Text('Limpar'))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: () {
                  setState(() { filtroTipo = tipo; filtroRaridade = raridade; filtroCategoria = categoria; });
                  Navigator.pop(sheetContext);
                }, child: const Text('Aplicar filtros'))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _abrirBuscaGlobal() async {
    // A pesquisa é construída diretamente do índice completo, nunca da lista
    // de pastas/imagens disponíveis no dispositivo.
    final indiceCompleto = await _carregarIndiceCartas();
    if (_cartasBuscaGlobalCache == null) {
    final colecoesPorId = <String, Colecao>{
      for (final colecao in colecoes) colecao.nome.split('_').first: colecao,
    };
    // O cache de coleções só contém imagens das coleções já abertas.
    // Para a busca global, indexamos os arquivos reais de todas as pastas.
    final imagensPorChave = <String, File>{};
    for (final colecao in colecoes) {
      final id = colecao.nome.split('_').first;
      await for (final item in colecao.pasta.list(recursive: true, followLinks: false)) {
        if (item is! File) continue;
        final nomeArquivo = item.uri.pathSegments.isNotEmpty
            ? item.uri.pathSegments.last
            : item.path.split(Platform.pathSeparator).last;
        final ponto = nomeArquivo.lastIndexOf('.');
        final ext = ponto >= 0 ? nomeArquivo.substring(ponto).toLowerCase() : '';
        if (!extensoesImagem.contains(ext)) continue;
        imagensPorChave['$id|${_normalizarChave(nomeArquivo)}'] = item;
        final slugLocal = _slugDoArquivoLocal(nomeArquivo);
        if (slugLocal.isNotEmpty) imagensPorChave['$id|${_normalizarChave(slugLocal)}'] = item;
      }
    }
    final cartasPreparadas = <Carta>[];
    for (final entry in indiceCompleto.entries) {
      final dados = entry.value;
      final id = _texto(dados, 'collectionId');
      final arquivo = _arquivoDaCarta(dados);
      if (id.isEmpty) continue;
      final imagem = arquivo.isEmpty
          ? null
          : imagensPorChave['$id|${_normalizarChave(arquivo)}'];
      final colecao = colecoesPorId[id];
      final nome = _texto(dados, 'name').trim();
      final slug = _texto(dados, 'slug').trim();
      final identificadorVisual = arquivo.isNotEmpty
          ? arquivo
          : (slug.isNotEmpty ? slug : 'carta_sem_imagem');
      final nomeColecao = _texto(dados, 'collectionName').trim();
      cartasPreparadas.add(Carta(
        nome: nome.isNotEmpty ? nome : (slug.isNotEmpty ? slug : identificadorVisual),
        arquivo: imagem ?? File('/__tcg_missing_image__/$identificadorVisual'),
        dados: dados,
        collectionName: nomeColecao.isNotEmpty
            ? nomeColecao
            : (colecao?.nome.replaceFirst(RegExp(r'^\\d+_'), '').replaceAll('_', ' ') ?? ''),
        collectionId: id,
      ));
    }
    final chavesBusca = <String>{};
    for (final carta in cartasPreparadas) {
      final slug = _texto(carta.dados, 'slug').trim();
      final arquivo = carta.arquivo.uri.pathSegments.isEmpty ? carta.arquivo.path.split(Platform.pathSeparator).last : carta.arquivo.uri.pathSegments.last;
      final identificador = slug.isNotEmpty ? slug : _slugDoArquivoLocal(arquivo);
      chavesBusca.add(carta.collectionId + '|' + _normalizarChave(identificador));
    }
    for (final colecao in colecoes) {
      final cartasLocais = await _carregarCartasDaColecao(colecao);
      for (final carta in cartasLocais) {
        final slug = _texto(carta.dados, 'slug').trim();
        final arquivo = carta.arquivo.uri.pathSegments.isEmpty ? carta.arquivo.path.split(Platform.pathSeparator).last : carta.arquivo.uri.pathSegments.last;
        final identificador = slug.isNotEmpty ? slug : _slugDoArquivoLocal(arquivo);
        final chave = carta.collectionId + '|' + _normalizarChave(identificador);
        if (identificador.isNotEmpty && chavesBusca.add(chave)) cartasPreparadas.add(carta);
      }
    }
    _cartasBuscaGlobalCache = cartasPreparadas;
    }
    final todasCartas = _cartasBuscaGlobalCache!;
    final categoriasBusca = todasCartas.map(_categoriaDaCarta).toSet().toList()..sort();
    final controller = TextEditingController();
    Timer? debounceBusca;
    var categoriaSelecionada = 'Todos';
    var ordemBusca = 'recentes';
    final preferenciasBusca = await SharedPreferences.getInstance();
    ordemBusca = preferenciasBusca.getString('ordem_busca_global') ?? 'recentes';
    var resultadosAtuais = <Carta>[];

    final nomesPesquisa = <Carta, String>{
      for (final carta in todasCartas)
        carta: _normalizarChave(
          _texto(carta.dados, 'name').replaceAll(RegExp(r'\([^)]*\\)'), ' '),
        ),
    };
    final ordemColecao = <String, int>{
      for (var i = 0; i < colecoes.length; i++)
        _normalizarChave(colecoes[i].nome.replaceFirst(RegExp(r'^\\d+_'), '').replaceAll('_', ' ')): i,
    };
    final numerosPesquisa = <Carta, int>{
      for (final carta in todasCartas)
        carta: int.tryParse(
          RegExp(r'^\\d+').firstMatch(_texto(carta.dados, 'number'))?.group(0) ?? '',
        ) ?? 999999,
    };

    List<Carta> buscar(String texto) {
      final termo = _normalizarChave(texto);
      if (termo.isEmpty) return <Carta>[];

      const tiposConhecidos = {
        'grass', 'grama', 'planta', 'fire', 'fogo', 'water', 'agua',
        'lightning', 'eletrico', 'electric', 'psychic', 'psiquico',
        'fighting', 'lutador', 'darkness', 'sombrio', 'noturno',
        'metal', 'metalico', 'fairy', 'fada', 'dragon', 'dragao',
        'colorless', 'incolor',
      };
      final ehBuscaTipo = tiposConhecidos.contains(termo);
      final ehBuscaNumero =
          RegExp(r'^\\d+(?:\\s*/\\s*\\d+)?$').hasMatch(texto.trim());

      final nomesEncontrados = <Carta>[];
      if (!ehBuscaTipo && !ehBuscaNumero) {
        for (final carta in todasCartas) {
          if ((nomesPesquisa[carta] ?? '').contains(termo)) {
            nomesEncontrados.add(carta);
          }
        }
      }

      final colecaoEncontrada = !ehBuscaTipo &&
          !ehBuscaNumero &&
          nomesEncontrados.isEmpty &&
          colecoes.any((colecao) =>
              _normalizarChave(colecao.nome).contains(termo));

      final resultados = <Carta>[];
      final candidatos = nomesEncontrados.isNotEmpty
          ? nomesEncontrados
          : (colecaoEncontrada ? todasCartas : todasCartas);

      for (final carta in candidatos) {
        final categoria = _categoriaDaCarta(carta);
        if (categoriaSelecionada != 'Todos' &&
            categoria != categoriaSelecionada) continue;

        if (ehBuscaTipo) {
          if (categoria != 'Pokémon' && categoria != 'Energia') continue;
          if (!_tiposDaCarta(carta).any(
            (tipo) => _tipoCanonico(tipo) == _tipoCanonico(termo),
          )) continue;
        } else if (ehBuscaNumero) {
          final numero = _texto(carta.dados, 'number').trim();
          final numeroDigitado = texto.trim();
          if (_normalizarChave(numero) != termo &&
              !RegExp('^' + RegExp.escape(numeroDigitado) + r'(?:\\s*/|\\s|$)')
                  .hasMatch(numero)) continue;
        } else if (nomesEncontrados.isNotEmpty) {
          // Correspondência exclusivamente com o nome canônico da carta.
          // Descrição, texto de efeito, slug e nome de arquivo não participam.
          if (!(nomesPesquisa[carta] ?? '').contains(termo)) continue;
        } else if (colecaoEncontrada) {
          if (!_normalizarChave(carta.collectionName).contains(termo)) continue;
        } else {
          continue;
        }
        resultados.add(carta);
      }

      resultados.sort((a, b) {
        final nomeA = _normalizarChave(a.collectionName);
        final nomeB = _normalizarChave(b.collectionName);
        final indiceA = ordemColecao[nomeA] ?? 999999;
        final indiceB = ordemColecao[nomeB] ?? 999999;
        final lancamento = ordemBusca == 'recentes'
            ? indiceB.compareTo(indiceA)
            : indiceA.compareTo(indiceB);
        if (lancamento != 0) return lancamento;
        final numero = (numerosPesquisa[a] ?? 999999)
            .compareTo(numerosPesquisa[b] ?? 999999);
        if (numero != 0) return numero;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });
      return resultados;
    }

    Future<void> abrirResultados(
      BuildContext sheetContext,
      List<Carta> resultados,
    ) async {
      final termo = controller.text.trim();
      if (termo.isEmpty || resultados.isEmpty) return;
      // Mantém a pesquisa na pilha para que Voltar retorne ao campo de busca.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BuscaGlobalResultadosScreen(
            termo: termo,
            cartas: resultados,
          ),
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, atualizar) {
          final resultados = resultadosAtuais;
          final categorias = categoriasBusca;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16, 8, 16,
                MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * .82,
                child: Column(children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pesquisa global de cartas',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      debounceBusca?.cancel();
                      debounceBusca = Timer(const Duration(milliseconds: 450), () {
                        atualizar(() { resultadosAtuais = buscar(controller.text); });
                      });
                    },
                    onSubmitted: (_) {
                      resultadosAtuais = buscar(controller.text);
                      abrirResultados(sheetContext, resultadosAtuais);
                    },
                    decoration: InputDecoration(
                      hintText: 'Nome, número, Pokémon, tipo ou coleção',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Mostrar resultados',
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: () => abrirResultados(sheetContext, resultados),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: categoriaSelecionada,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Todos', ...categorias]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => atualizar(() {
                      categoriaSelecionada = v ?? 'Todos';
                      resultadosAtuais = buscar(controller.text);
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: ordemBusca,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Ordem de lançamento',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'recentes', child: Text('Mais recentes primeiro')),
                      DropdownMenuItem(value: 'antigos', child: Text('Mais antigos primeiro')),
                    ],
                    onChanged: (v) async {
                      final novaOrdem = v ?? 'recentes';
                      ordemBusca = novaOrdem;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('ordem_busca_global', novaOrdem);
                      atualizar(() { resultadosAtuais = buscar(controller.text); });
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      controller.text.trim().isEmpty
                          ? 'Digite para ver sugestões'
                          : '${resultados.length} cartas encontradas',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: resultados.isEmpty
                        ? Center(
                            child: Text(
                              controller.text.trim().isEmpty
                                  ? 'As sugestões aparecerão aqui.'
                                  : 'Nenhuma carta encontrada.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: resultados.length > 80 ? 80 : resultados.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final carta = resultados[index];
                              final numero = _texto(carta.dados, 'number');
                              final tipos = _tiposDaCarta(carta).join(' • ');
                              return ListTile(
                                leading: SizedBox(
                                  width: 48,
                                  height: 64,
                                  child: Image.file(
                                    carta.arquivo,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image),
                                  ),
                                ),
                                title: Text(
                                  carta.nome,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${carta.collectionName}'
                                  '${numero.isEmpty ? '' : ' • $numero'}'
                                  '${tipos.isEmpty ? '' : ' • $tipos'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CartaDetalheScreen(carta: carta),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  if (resultados.length > 80)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Mostrando 80 sugestões. Pressione Enter para abrir todos os resultados.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: resultados.isEmpty
                          ? null
                          : () => abrirResultados(sheetContext, resultados),
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Abrir resultados'),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
    debounceBusca?.cancel();
    controller.dispose();
  }

  String _nomePasta(Directory pasta) {
    final caminho = pasta.path.endsWith(Platform.pathSeparator)
        ? pasta.path.substring(0, pasta.path.length - 1)
        : pasta.path;
    return caminho.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    final selecionada = colecaoSelecionada;
    final cartasExibidas = selecionada?.cartas.where(_cartaPassaFiltros).toList() ?? <Carta>[];

    return WillPopScope(
      onWillPop: () async {
        if (colecaoSelecionada != null) {
          setState(() {
            colecaoSelecionada = null;
            filtroTipo = 'Todos';
            filtroRaridade = 'Todas';
            filtroCategoria = 'Todas';
          });
          _restaurarPosicaoCatalogo();
          return false;
        }
        return true;
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(selecionada == null ? 'Cartas' : selecionada.nome),
        actions: [
          IconButton(tooltip: 'Pesquisa global', onPressed: colecoes.isEmpty ? null : _abrirBuscaGlobal, icon: const Icon(Icons.manage_search)),
          if (selecionada != null)
            IconButton(tooltip: 'Filtrar cartas', onPressed: _abrirFiltrosColecao, icon: const Icon(Icons.filter_list)),
          ValueListenableBuilder<bool>(
            valueListenable: modoEscuroGlobal,
            builder: (context, escuro, _) => IconButton(
              tooltip: escuro ? 'Ativar modo claro' : 'Ativar modo escuro',
              onPressed: () async {
                final novoTema = !escuro;
                modoEscuroGlobal.value = novoTema;
                final preferencias = await SharedPreferences.getInstance();
                await preferencias.setBool('modo_escuro', novoTema);
              },
              icon: Icon(escuro ? Icons.light_mode : Icons.dark_mode)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: carregarColecoes, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: carregando || erroMsg.isNotEmpty || colecoes.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _abrirBuscaColecao,
              icon: const Icon(Icons.search),
              label: const Text('Buscar coleção'),
            ),
      body: carregando || carregandoColecao
          ? const Center(child: CircularProgressIndicator())
          : erroMsg.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 42),
                        const SizedBox(height: 12),
                        Text(erroMsg, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: carregarColecoes,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : selecionada == null
                  ? GridView.builder(
                      key: const PageStorageKey<String>('catalogo-colecoes'),
                      controller: _catalogoScrollController,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.18,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: colecoes.length,
                      itemBuilder: (context, index) {
                        final item = colecoes[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            _catalogoScrollOffset = _catalogoScrollController.hasClients
                                ? _catalogoScrollController.offset
                                : _catalogoScrollOffset;
                            _abrirColecao(item);
                          },
                          child: Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: item.logo != null
                                        ? Image.file(
                                            item.logo!,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.collections_outlined, size: 42),
                                          )
                                        : const Icon(Icons.collections_outlined, size: 42),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.nome.replaceFirst(RegExp(r'^\d+_'), '').replaceAll('_', ' '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text('${item.totalCartas} cartas',
                                      style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : selecionada.cartas.isEmpty
                      ? const Center(child: Text('Nenhuma imagem encontrada nesta coleção.'))
                      : cartasExibidas.isEmpty
                          ? const Center(child: Text('Nenhuma carta corresponde aos filtros.'))
                          : Column(children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                child: Row(children: [
                                  Expanded(child: Text('${cartasExibidas.length} de ${selecionada.cartas.length} cartas')),
                                  TextButton.icon(onPressed: _abrirFiltrosColecao, icon: const Icon(Icons.filter_list), label: const Text('Filtros')),
                                ]),
                              ),
                              Expanded(child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.68,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: cartasExibidas.length,
                          itemBuilder: (context, index) {
                            final carta = cartasExibidas[index];
                            return InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CartaDetalheScreen(carta: carta),
                                ),
                              ),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: Image.file(
                                  carta.arquivo,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image, size: 42),
                                ),
                              ),
                            );
                          },
                        )),
                              ]),
    ),
    );
  }
}

class CartasScreen extends StatelessWidget {
  final Colecao colecao;

  const CartasScreen({super.key, required this.colecao});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(colecao.nome)),
      body: colecao.cartas.isEmpty
          ? const Center(child: Text('Nenhuma imagem encontrada nesta coleção.'))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.68,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: colecao.cartas.length,
              itemBuilder: (context, index) {
                final carta = colecao.cartas[index];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CartaDetalheScreen(carta: carta),
                    ),
                  ),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(
                      carta.arquivo,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.image_not_supported_outlined, size: 34),
                            const SizedBox(height: 10),
                            Text(carta.nome, textAlign: TextAlign.center,
                              maxLines: 3, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Text((carta.dados?['number'] ?? '').toString(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall),
                            Text(carta.collectionName, textAlign: TextAlign.center,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class BuscaGlobalResultadosScreen extends StatelessWidget {
  final String termo;
  final List<Carta> cartas;

  const BuscaGlobalResultadosScreen({
    super.key,
    required this.termo,
    required this.cartas,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultados da busca'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '"$termo"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${cartas.length} cartas'),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.68,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: cartas.length,
              itemBuilder: (context, index) {
                final carta = cartas[index];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CartaDetalheScreen(carta: carta),
                    ),
                  ),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(
                      carta.arquivo,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 42),
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

class CartaDetalheScreen extends StatelessWidget {
  final Carta carta;

  const CartaDetalheScreen({super.key, required this.carta});

  Future<void> copiarParaDownload(BuildContext context) async {
    try {
      final pastaDownload = Directory('/sdcard/Download');
      if (!await pastaDownload.exists()) {
        await pastaDownload.create(recursive: true);
      }
      final nomeArquivo = carta.arquivo.uri.pathSegments.last;
      final destino = File('${pastaDownload.path}/$nomeArquivo');
      await carta.arquivo.copy(destino.path);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Carta copiada para Downloads!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao copiar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(carta.nome)),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child: Image.file(
                  carta.arquivo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 64),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => copiarParaDownload(context),
              icon: const Icon(Icons.download),
              label: const Text('Copiar para Downloads'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// CI: dispara validação da branch da PR sem alterar o comportamento do aplicativo.
