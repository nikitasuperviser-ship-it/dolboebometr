import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'episode_result.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Dolboebometr());
}

const purple = Color(0xFF955DFF);
const pink = Color(0xFFFF557E);
const bg = Color(0xFF0A0D16);
const panel = Color(0xFF171B2C);

class Dolboebometr extends StatelessWidget {
  const Dolboebometr({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Долбоёбометр',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: purple, brightness: Brightness.dark,
      ),
    ),
    home: const CameraPage(),
  );
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
    with WidgetsBindingObserver {
  CameraController? camera;
  List<CameraDescription> devices = [];
  int cameraIndex = 0;
  bool busy = false;
  bool consent = false;
  String message = 'Запускаем камеру…';
  String endpoint = '';
  String token = '';
  EpisodeResult? result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(openCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final old = camera;
      camera = null;
      if (mounted) setState(() {});
      if (old != null) unawaited(old.dispose());
    } else if (state == AppLifecycleState.resumed && !busy) {
      unawaited(openCamera());
    }
  }

  Future<void> openCamera() async {
    try {
      if (devices.isEmpty) devices = await availableCameras();
      if (devices.isEmpty) throw StateError('Камера не найдена');
      final old = camera;
      camera = null;
      if (old != null) await old.dispose();
      final next = CameraController(
        devices[cameraIndex], ResolutionPreset.medium,
        enableAudio: false,
      );
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        message = '';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Ошибка камеры: $e');
    }
  }

  Future<void> flipCamera() async {
    if (busy || devices.length < 2) return;
    setState(() => cameraIndex = (cameraIndex + 1) % devices.length);
    await openCamera();
  }

  void notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> settings() async {
    final url = TextEditingController(text: endpoint);
    final secret = TextEditingController(text: token);
    final values = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: panel,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 24, 20, 24 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Настройки ИИ', style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 22)),
              const SizedBox(height: 12),
              const Text('Для настоящего анализа требуется отдельный сервер. '
                'API-ключ ИИ нельзя хранить в приложении.'),
              const SizedBox(height: 14),
              TextField(controller: url, keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'HTTPS адрес /analyze',
                  hintText: 'https://example.com/analyze',
                )),
              const SizedBox(height: 10),
              TextField(controller: secret, obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Токен доступа (необязательно)',
                )),
              const SizedBox(height: 15),
              FilledButton(onPressed: () {
                Navigator.pop(ctx, (url.text.trim(), secret.text.trim()));
              }, child: const Text('Сохранить')),
            ],
          ),
        ),
      ),
    );
    if (values != null && mounted) {
      final (newUrl, newToken) = values;
      if (newUrl.isNotEmpty &&
          Uri.tryParse(newUrl)?.scheme != 'https') {
        notify('Используйте HTTPS адрес сервера.');
        return;
      }
      setState(() {
        endpoint = newUrl;
        token = newToken;
      });
    }
  }

  Future<void> analyze() async {
    if (busy) return;
    if (!consent) {
      notify('Подтвердите согласие участников на съёмку.');
      return;
    }
    final activeCamera = camera;
    if (activeCamera == null || !activeCamera.value.isInitialized) {
      notify('Камера ещё не готова.');
      return;
    }
    if (endpoint.isEmpty) {
      notify('Для анализа нужно настроить HTTPS сервер. '
        'Пока доступен демонстрационный режим.');
      return;
    }
    setState(() {
      busy = true;
      result = null;
      message = 'Записываем пять кадров эпизода…';
    });
    try {
      final frames = <String>[];
      for (var index = 0; index < 5; index++) {
        if (index > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }
        if (!mounted) return;
        final photo = await activeCamera.takePicture();
        try {
          frames.add(base64Encode(await File(photo.path).readAsBytes()));
        } finally {
          try { await File(photo.path).delete(); } catch (_) {}
        }
      }
      if (mounted) setState(() => message = 'ИИ анализирует эпизод…');
      final response = await http.post(Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'X-App-Token': token,
        },
        body: jsonEncode({'images': frames}),
      ).timeout(const Duration(seconds: 80));
      if (response.statusCode != 200) {
        throw StateError('Сервер ответил кодом ${response.statusCode}');
      }
      final parsed = jsonDecode(utf8.decode(response.bodyBytes));
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Неожиданный ответ ИИ');
      }
      if (mounted) setState(() => result = EpisodeResult.fromJson(parsed));
    } catch (e) {
      notify('Не удалось проанализировать: $e');
    } finally {
      if (mounted) setState(() {
        busy = false;
        message = '';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final active = camera;
    if (active != null) unawaited(active.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = camera;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const Icon(Icons.center_focus_strong, color: purple),
              const SizedBox(width: 8),
              const Expanded(child: Text('ДОЛБОЁБОМЕТР',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w900))),
              if (device != null) const Text('● LIVE',
                style: TextStyle(color: pink, fontWeight: FontWeight.bold)),
              IconButton(tooltip: 'Настройки', onPressed: busy ? null : settings,
                icon: const Icon(Icons.settings_outlined)),
            ]),
          ),
          Expanded(flex: 6, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(borderRadius: BorderRadius.circular(20),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: const Color(0xFF1A1D28)),
                if (device != null && device.value.isInitialized)
                  CameraPreview(device)
                else Center(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(message.isEmpty ? 'Камера недоступна' : message,
                    textAlign: TextAlign.center),
                )),
                Positioned(top: 16, left: 16, child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xC5000000),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Text('ОБЛАСТЬ СЪЁМКИ · БЕЗ ТРЕКИНГА',
                    style: TextStyle(fontSize: 10)),
                )),
                Center(child: IgnorePointer(child: Container(
                  width: 220, height: 270,
                  decoration: BoxDecoration(border: Border.all(
                    color: const Color(0xFF65D9B5), width: 1.7),
                    borderRadius: BorderRadius.circular(14)),
                ))),
                Positioned(right: 10, bottom: 10,
                  child: IconButton.filledTonal(
                    tooltip: 'Переключить камеру',
                    onPressed: busy ? null : flipCamera,
                    icon: const Icon(Icons.cameraswitch_outlined),
                  )),
                if (busy) Center(child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: panel,
                    borderRadius: BorderRadius.circular(16)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(color: purple),
                    const SizedBox(height: 12),
                    Text(message),
                  ]),
                )),
              ]),
            ),
          )),
          Expanded(flex: 5, child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: panel,
                    borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(child: Text('ИНДЕКС АБСУРДА',
                          style: TextStyle(fontWeight: FontWeight.w800))),
                        Text(result?.score == null ? '—/100' :
                          '${result!.score}/100', style: const TextStyle(
                          color: pink, fontSize: 26,
                          fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: (result?.score ?? 0) / 100,
                          backgroundColor: const Color(0xFF35374D),
                          color: purple, minHeight: 9)),
                      const SizedBox(height: 14),
                      if (result?.demo ?? false)
                        const Text('ДЕМО — ВЫМЫШЛЕННЫЙ ЭПИЗОД',
                          style: TextStyle(color: pink,
                            fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(result?.observation ??
                        'Наведите камеру на действие и запустите анализ.'),
                      if (result != null && result!.comment.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(result!.comment,
                          style: const TextStyle(color: Color(0xFFDBBBFF))),
                      ],
                    ]),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: consent,
                  onChanged: busy ? null : (v) {
                    setState(() => consent = v ?? false);
                  },
                  title: const Text('Участники согласны на съёмку',
                    style: TextStyle(fontSize: 13)),
                  subtitle: const Text('При анализе 5 кадров передаются '
                    'на настроенный сервер. Звук не записывается.',
                    style: TextStyle(fontSize: 11)),
                ),
                SizedBox(height: 52, child: FilledButton.icon(
                  onPressed: busy ? null : analyze,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('ОЦЕНИТЬ ЭПИЗОД',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(backgroundColor: purple),
                )),
                TextButton.icon(
                  onPressed: busy ? null : () => setState(() {
                    result = EpisodeResult.demoResult;
                  }),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Посмотреть ДЕМО'),
                ),
                const Text('Шуточная оценка только наблюдаемого действия, '
                  'не внешности, личности или интеллекта.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white60)),
              ]),
          )),
        ]),
      ),
    );
  }
}
