import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

const String raizColecoes = '/sdcard/meuapp/tcg físico';
const Set<String> extensoesImagem = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PokemonTcgApp());
}

class PokemonTcgApp extends StatelessWidget {
  const PokemonTcgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokemon TCG Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ColecoesScreen(),
    );
  }
}

class Carta {
  final String nome;
  final File arquivo;

  const Carta({required this.nome, required this.arquivo});
}

class Colecao {
  final String nome;
  final Directory pasta;
  final List<Carta> cartas;
  final File? logo;

  const Colecao({
    required this.nome,
    required this.pasta,
    required this.cartas,
    this.logo,
  });
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
  String erroMsg = '';

  @override
  void initState() {
    super.initState();
    carregarColecoes();
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

  Future<void> carregarColecoes() async {
    if (mounted) {
      setState(() {
        carregando = true;
        erroMsg = '';
      });
    }

    try {
      final permitido = await garantirPermissao();
      if (!permitido) {
        if (mounted) {
          setState(() {
            erroMsg = 'Permissão de acesso aos arquivos não concedida.';
            carregando = false;
          });
        }
        return;
      }

      // Localiza "tcg fisico" sem depender de acentos ou caixa.
      final pastaBase = Directory('/sdcard/meuapp');
      if (!await pastaBase.exists()) {
        throw Exception('Pasta /sdcard/meuapp não encontrada.');
      }

      String normalizarNome(String valor) {
        return valor.toLowerCase()
            .replaceAll('á', 'a').replaceAll('à', 'a')
            .replaceAll('ã', 'a').replaceAll('â', 'a')
            .replaceAll('é', 'e').replaceAll('ê', 'e')
            .replaceAll('í', 'i').replaceAll('ó', 'o')
            .replaceAll('ô', 'o').replaceAll('õ', 'o')
            .replaceAll('ú', 'u').replaceAll('ç', 'c')
            .trim();
      }

      Directory? raiz;
      final diretoriosEncontrados = <String>[];
      await for (final item in pastaBase.list(followLinks: false)) {
        if (item is Directory) {
          final nome = item.path.split(Platform.pathSeparator).last;
          diretoriosEncontrados.add(nome);
          if (normalizarNome(nome) == 'tcg fisico') {
            raiz = item;
            break;
          }
        }
      }

      if (raiz == null) {
        throw Exception(
          'Pasta "tcg fisico" não encontrada dentro de /sdcard/meuapp. '
          'Pastas encontradas: ${diretoriosEncontrados.isEmpty ? "(nenhuma)" : diretoriosEncontrados.join(", ")}'
        );
      }

      // Catálogo oficial de logos: cada pasta local começa com o ID da coleção.
      final pastaLogos = Directory('/sdcard/meuapp/logos');
      final arquivosLogo = <String, String>{};
      final ordemCatalogo = <String, int>{};
      final arquivoCatalogo = File('${pastaLogos.path}/catalogo.json');
      if (await arquivoCatalogo.exists()) {
        final dados = jsonDecode(await arquivoCatalogo.readAsString());
        if (dados is List) {
          for (var i = 0; i < dados.length; i++) {
            final item = dados[i];
            if (item is Map) {
              final id = item['id']?.toString();
              final nomeArquivo = item['arquivo']?.toString();
              if (id != null && id.isNotEmpty && nomeArquivo != null) {
                arquivosLogo[id] = nomeArquivo;
                ordemCatalogo[id] = i;
              }
            }
          }
        }
      }

      String idDaPasta(Directory pasta) {
        final nome = _nomePasta(pasta);
        final separador = nome.indexOf('_');
        return separador > 0 ? nome.substring(0, separador) : nome;
      }

      final pastas = <Directory>[];
      await for (final item in raiz.list(followLinks: false)) {
        if (item is Directory) pastas.add(item);
      }
      pastas.sort((a, b) {
        final idA = idDaPasta(a);
        final idB = idDaPasta(b);
        final posA = ordemCatalogo[idA] ?? 999999;
        final posB = ordemCatalogo[idB] ?? 999999;
        if (posA != posB) return posA.compareTo(posB);
        return _nomePasta(a).toLowerCase().compareTo(_nomePasta(b).toLowerCase());
      });

      final resultado = <Colecao>[];
      for (final pasta in pastas) {
        final cartas = <Carta>[];
        await for (final item in pasta.list(followLinks: false)) {
          if (item is File) {
            final nomeArquivo = item.uri.pathSegments.isNotEmpty
                ? item.uri.pathSegments.last
                : item.path.split(Platform.pathSeparator).last;
            final ponto = nomeArquivo.lastIndexOf('.');
            final extensao = ponto >= 0 ? nomeArquivo.substring(ponto).toLowerCase() : '';
            if (extensoesImagem.contains(extensao)) {
              final nome = ponto > 0 ? nomeArquivo.substring(0, ponto) : nomeArquivo;
              cartas.add(Carta(nome: nome, arquivo: item));
            }
          }
        }
        cartas.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
        final id = idDaPasta(pasta);
        final nomeLogo = arquivosLogo[id];
        final arquivoLogo = nomeLogo == null ? null : File('${pastaLogos.path}/$nomeLogo');
        resultado.add(Colecao(
          nome: _nomePasta(pasta),
          pasta: pasta,
          cartas: cartas,
          logo: arquivoLogo != null && await arquivoLogo.exists() ? arquivoLogo : null,
        ));
      }

      if (mounted) {
        setState(() {
          colecoes = resultado;
          if (colecaoSelecionada != null) {
            final caminhoSelecionado = colecaoSelecionada!.pasta.path;
            Colecao? encontrada;
            for (final item in resultado) {
              if (item.pasta.path == caminhoSelecionado) {
                encontrada = item;
                break;
              }
            }
            colecaoSelecionada = encontrada;
          }
          carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          erroMsg = 'Erro ao carregar coleções: $e';
          carregando = false;
        });
      }
    }
  }

  Future<void> _abrirSeletorColecao() async {
    if (colecoes.isEmpty) return;

    final selecionada = await showModalBottomSheet<Colecao>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.70,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Selecionar coleção',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.18,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: colecoes.length,
                  itemBuilder: (context, index) {
                    final item = colecoes[index];
                    final ativa = colecaoSelecionada?.pasta.path == item.pasta.path;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(sheetContext, item),
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: ativa
                              ? const BorderSide(color: Colors.blue, width: 2)
                              : BorderSide.none,
                        ),
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
                              Text('${item.cartas.length} cartas',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selecionada != null && mounted) {
      setState(() => colecaoSelecionada = selecionada);
    }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(selecionada == null ? 'Cartas' : selecionada.nome),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregarColecoes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: carregando || erroMsg.isNotEmpty || colecoes.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _abrirSeletorColecao,
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: Text(selecionada == null ? 'Selecionar coleção' : 'Trocar coleção'),
            ),
      body: carregando
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
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.collections_bookmark_outlined, size: 64),
                            const SizedBox(height: 16),
                            const Text(
                              'Selecione uma coleção para visualizar suas cartas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _abrirSeletorColecao,
                              icon: const Icon(Icons.list),
                              label: const Text('Escolher coleção'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : selecionada.cartas.isEmpty
                      ? const Center(child: Text('Nenhuma imagem encontrada nesta coleção.'))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.68,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: selecionada.cartas.length,
                          itemBuilder: (context, index) {
                            final carta = selecionada.cartas[index];
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
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 42),
                    ),
                  ),
                );
              },
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
