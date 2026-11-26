import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const PokemonTcgApp());
}

class PokemonTcgApp extends StatelessWidget {
  const PokemonTcgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokemon TCG Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ColecoesScreen(),
    );
  }
}

class ColecoesScreen extends StatefulWidget {
  const ColecoesScreen({super.key});
  @override
  State<ColecoesScreen> createState() => _ColecoesScreenState();
}

class _ColecoesScreenState extends State<ColecoesScreen> {
  List<dynamic> colecoes = [];
  bool carregando = true;
  String erroMsg = '';

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  Future<void> carregarDados() async {
    // Pede permissão de armazenamento (para Android antigo e novo)
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    try {
      final file = File('/sdcard/meuapp/dados.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        setState(() {
          colecoes = jsonDecode(jsonString);
          carregando = false;
        });
      } else {
        setState(() {
          erroMsg = 'Arquivo dados.json não encontrado em /sdcard/meuapp/';
          carregando = false;
        });
      }
    } catch (e) {
      setState(() {
        erroMsg = 'Erro ao ler dados: $e';
        carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coleções')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erroMsg.isNotEmpty
              ? Center(child: Text(erroMsg, style: const TextStyle(color: Colors.red)))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: colecoes.length,
                  itemBuilder: (context, index) {
                    final colecao = colecoes[index];
                    final primeiraCarta = colecao['cartas'].isNotEmpty ? colecao['cartas'][0]['caminhoCompleto'] : null;

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CartasScreen(colecao: colecao),
                          ),
                        );
                      },
                      child: Card(
                        child: Column(
                          children: [
                            Expanded(
                              child: primeiraCarta != null
                                  ? Image.file(File(primeiraCarta), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image))
                                  : const Icon(Icons.image),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                colecao['nome'],
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
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
  final dynamic colecao;
  const CartasScreen({super.key, required this.colecao});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(colecao['nome'])),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.7,
        ),
        itemCount: colecao['cartas'].length,
        itemBuilder: (context, index) {
          final carta = colecao['cartas'][index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CartaDetalheScreen(carta: carta),
                ),
              );
            },
            child: Card(
              child: Image.file(File(carta['caminhoCompleto']), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
            ),
          );
        },
      ),
    );
  }
}

class CartaDetalheScreen extends StatelessWidget {
  final dynamic carta;
  const CartaDetalheScreen({super.key, required this.carta});

  Future<void> copiarParaDownload(BuildContext context) async {
    try {
      final arquivoOrigem = File(carta['caminhoCompleto']);
      final pastaDownload = Directory('/sdcard/Download');
      final nomeArquivo = carta['arquivo'];
      final arquivoDestino = File('${pastaDownload.path}/$nomeArquivo');

      await arquivoOrigem.copy(arquivoDestino.path);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carta copiada para Download!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao copiar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(carta['nome'])),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.file(File(carta['caminhoCompleto']), errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
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
