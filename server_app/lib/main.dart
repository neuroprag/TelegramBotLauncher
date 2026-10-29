import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ТГ-бот на телефоне',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final tokenCtrl = TextEditingController();
  final greetCtrl = TextEditingController(text: 'Привет! Я бот на телефоне.');
  bool echo = true;
  bool running = false;
  int offset = 0;
  http.Client? client;
  String status = 'Бот выключен';
  final List<String> log = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      tokenCtrl.text = p.getString('token') ?? '';
      greetCtrl.text = p.getString('greet') ?? greetCtrl.text;
      echo = p.getBool('echo') ?? true;
    });
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', tokenCtrl.text.trim());
    await p.setString('greet', greetCtrl.text);
    await p.setBool('echo', echo);
  }

  void addLog(String s) {
    if (!mounted) return;
    setState(() {
      log.insert(0, '${DateTime.now().toString().substring(11, 19)}  $s');
      if (log.length > 50) log.removeLast();
    });
  }

  Future<void> start() async {
    final token = tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => status = 'Сначала вставь токен бота');
      return;
    }
    await save();
    client = http.Client();
    try {
      final r = await client!
          .get(Uri.parse('https://api.telegram.org/bot$token/getMe'))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d['ok'] != true) {
        setState(() => status = 'Токен не подошёл');
        return;
      }
      setState(() {
        running = true;
        status = 'Работает: @${d['result']['username']}';
      });
      loop(token);
    } catch (e) {
      setState(() => status = 'Нет связи с Telegram (нужен VPN?)');
    }
  }

  Future<void> stop() async {
    running = false;
    client?.close();
    setState(() => status = 'Бот выключен');
  }

  Future<void> loop(String token) async {
    final c = client!;
    while (running) {
      try {
        final r = await c
            .get(Uri.parse(
                'https://api.telegram.org/bot$token/getUpdates?timeout=25&offset=$offset'))
            .timeout(const Duration(seconds: 40));
        final d = jsonDecode(r.body);
        if (d['ok'] != true) {
          addLog('Ошибка: ${d['description']}');
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }
        for (final u in d['result']) {
          offset = (u['update_id'] as int) + 1;
          final m = u['message'];
          if (m == null || m['text'] == null) continue;
          await handle(c, token, m);
        }
      } catch (e) {
        if (!running) break;
        addLog('Сеть: $e');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  Future<void> handle(http.Client c, String token, dynamic m) async {
    final text = m['text'] as String;
    final chatId = m['chat']['id'].toString();
    addLog('Сообщение: $text');
    String? reply;
    if (text == '/start') {
      reply = greetCtrl.text;
    } else if (text == '/ping') {
      reply = 'pong';
    } else if (echo) {
      reply = 'Ты написал: $text';
    }
    if (reply == null) return;
    await c.post(
      Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
      body: {'chat_id': chatId, 'text': reply},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ТГ-бот на телефоне')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: tokenCtrl,
            enabled: !running,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Токен бота',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Настройки'),
            children: [
              TextField(
                controller: greetCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ответ на /start',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => save(),
              ),
              SwitchListTile(
                title: const Text('Повторять сообщения (эхо)'),
                value: echo,
                onChanged: (v) {
                  setState(() => echo = v);
                  save();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: running ? stop : start,
            child: Text(running ? 'Остановить бота' : 'Запустить бота'),
          ),
          const SizedBox(height: 12),
          Text(status, style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 32),
          for (final l in log) Text(l),
        ],
      ),
    );
  }
}
