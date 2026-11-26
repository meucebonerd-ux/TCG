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

// Tela 1: Lista de Coleções
class ColecoesScreen extends StatefulWidget {
  const ColecoesScreen({super.key});
  @override
  State<ColecoesScreen> createState() => _ColecoesScreenState();
}

class _ColecoesScreenState extends State<ColecoesScreen> {
  List<dynamic> colecoes = [];

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  Future<void> carregarDados() async {
    // Pede permissão de armazenamento
    await Permission.storage.request();
    
    try {
      // Lê o arquivo JSON gerado no Termux
      final file = File('/sdcard/meuapp/dados.json');
      final jsonString = await file.readAsString();
      setState(() {
        colecoes = jsonDecode(jsonString);
      });
    } catch (e) {
      print("Erro ao ler dados: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coleções')),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.7,
        ),
        itemCount: colecoes.length,
        itemBuilder: (context, index) {
          final colecao = colecoes[index];
          // Pega a primeira carta da coleção para usar como "logo"
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
                        ? Image.file(File(primeiraCarta), fit: BoxFit.cover)
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

// Tela 2: Lista de Cartas da Coleção
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
              child: Image.file(File(carta['caminhoCompleto']), fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
}

// Tela 3: Imagem Grande e Botão de Copiar
class CartaDetalheScreen extends StatelessWidget {
  final dynamic carta;
  const CartaDetalheScreen({super.key, required this.carta});

  Future<void> copiarParaDownload(BuildContext context) async {
    try {
      final arquivoOrigem = File(carta['caminhoCompleto']);
      // Obtém a pasta de downloads pública do Android
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
              child: Image.file(File(carta['caminhoCompleto'])),
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
