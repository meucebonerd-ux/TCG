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

  const Colecao({
    required this.nome,
    required this.pasta,
    required this.cartas,
  });
}

class ColecoesScreen extends StatefulWidget {
  const ColecoesScreen({super.key});

  @override
  State<ColecoesScreen> createState() => _ColecoesScreenState();
}

class _ColecoesScreenState extends State<ColecoesScreen> {
  List<Colecao> colecoes = [];
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

      final pastas = <Directory>[];
      await for (final item in raiz.list(followLinks: false)) {
        if (item is Directory) pastas.add(item);
      }
      pastas.sort((a, b) => _nomePasta(a).toLowerCase().compareTo(_nomePasta(b).toLowerCase()));

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
        resultado.add(Colecao(
          nome: _nomePasta(pasta),
          pasta: pasta,
          cartas: cartas,
        ));
      }

      if (mounted) {
        setState(() {
          colecoes = resultado;
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

  String _nomePasta(Directory pasta) {
    final caminho = pasta.path.endsWith(Platform.pathSeparator)
        ? pasta.path.substring(0, pasta.path.length - 1)
        : pasta.path;
    return caminho.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coleções'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregarColecoes,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
              : colecoes.isEmpty
                  ? const Center(child: Text('Nenhuma pasta de coleção encontrada.'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.68,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: colecoes.length,
                      itemBuilder: (context, index) {
                        final colecao = colecoes[index];
                        final capa = colecao.cartas.isNotEmpty ? colecao.cartas.first.arquivo : null;

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CartasScreen(colecao: colecao),
                              ),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: capa != null
                                        ? Image.file(
                                            capa,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.broken_image, size: 42),
                                          )
                                        : const Icon(Icons.photo_library_outlined, size: 42),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        colecao.nome,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      Text(
                                        '${colecao.cartas.length} cartas',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
