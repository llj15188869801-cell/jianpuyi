import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // 权限检查与环境诊断
  await _initSystem();

  runApp(const JianPuYiApp());
}

Future<void> _initSystem() async {
  // 请求权限
  await Permission.camera.request();
  await Permission.storage.request();

  // 环境诊断
  final directory = await getApplicationDocumentsDirectory();
  debugPrint('JianPuYi 数据存储路径: ${directory.path}');
}

// ==================== App 入口 ====================
class JianPuYiApp extends StatelessWidget {
  const JianPuYiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '简谱译',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E676),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: const ScanPage(),
    );
  }
}

// ==================== 音频引擎 ====================
/// 使用 AudioPlayer 生成不同频率的音符声音
class NotePlayer {
  static final NotePlayer instance = NotePlayer._();
  NotePlayer._();

  final Map<String, AudioPlayer> _players = {};
  bool _initialized = false;

  // 简谱音符 -> MIDI 音高
  static const Map<String, int> noteToMidi = {
    '1': 60,  // C4
    '2': 62,  // D4
    '3': 64,  // E4
    '4': 65,  // F4
    '5': 67,  // G4
    '6': 69,  // A4
    '7': 71,  // B4
    '1h': 72, // C5 高音
    '2h': 74, // D5
    '3h': 76, // E5
    '4h': 77, // F5
    '5h': 79, // G5
    '6h': 81, // A5
    '7h': 83, // B5
    '1l': 48, // C3 低音
    '2l': 50, // D3
    '3l': 52, // E3
    '4l': 53, // F3
    '5l': 55, // G3
    '6l': 57, // A3
    '7l': 59, // B3
  };

  /// MIDI 音高转频率 (Hz)
  double midiToFrequency(int midi) {
    return 440.0 * pow(2, (midi - 69) / 12.0);
  }

  /// 生成正弦波 WAV 数据
  Uint8List _generateWav(double frequency, double durationSec, {double volume = 0.8}) {
    final int sampleRate = 44100;
    final int numSamples = (sampleRate * durationSec).round();
    final int dataSize = numSamples * 2; // 16-bit mono
    final int fileSize = 36 + dataSize;

    final ByteData wav = ByteData(44 + dataSize);

    // WAV Header
    // "RIFF"
    wav.setUint8(0, 0x52); wav.setUint8(1, 0x49); wav.setUint8(2, 0x46); wav.setUint8(3, 0x46);
    wav.setUint32(4, fileSize, Endian.little);
    // "WAVE"
    wav.setUint8(8, 0x57); wav.setUint8(9, 0x41); wav.setUint8(10, 0x56); wav.setUint8(11, 0x45);
    // "fmt "
    wav.setUint8(12, 0x66); wav.setUint8(13, 0x6D); wav.setUint8(14, 0x74); wav.setUint8(15, 0x20);
    wav.setUint32(16, 16, Endian.little); // chunk size
    wav.setUint16(20, 1, Endian.little);  // PCM
    wav.setUint16(22, 1, Endian.little);  // mono
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    wav.setUint16(32, 2, Endian.little);  // block align
    wav.setUint16(34, 16, Endian.little); // bits per sample
    // "data"
    wav.setUint8(36, 0x64); wav.setUint8(37, 0x61); wav.setUint8(38, 0x74); wav.setUint8(39, 0x61);
    wav.setUint32(40, dataSize, Endian.little);

    // 生成正弦波 + ADSR 包络
    for (int i = 0; i < numSamples; i++) {
      double t = i / sampleRate;
      double envelope = 1.0;

      // Attack (0-5%)
      double attackEnd = durationSec * 0.05;
      // Release (最后 20%)
      double releaseStart = durationSec * 0.8;

      if (t < attackEnd) {
        envelope = t / attackEnd;
      } else if (t > releaseStart) {
        envelope = (durationSec - t) / (durationSec - releaseStart);
      }

      // 正弦波 + 轻微泛音（更像钢琴）
      double sample = sin(2 * pi * frequency * t) * 0.7 +
                      sin(2 * pi * frequency * 2 * t) * 0.2 +
                      sin(2 * pi * frequency * 3 * t) * 0.1;

      sample *= envelope * volume;

      int value = (sample * 32767).round().clamp(-32768, 32767);
      wav.setInt16(44 + i * 2, value, Endian.little);
    }

    return wav.buffer.asUint8List();
  }

  /// 播放一个音符
  Future<void> playNote(String note, {double durationSec = 0.5}) async {
    if (note == '-' || note == '0') {
      // 休止符，只等待
      await Future.delayed(Duration(milliseconds: (durationSec * 1000).round()));
      return;
    }

    final int? midi = noteToMidi[note];
    if (midi == null) return;

    final double freq = midiToFrequency(midi);
    final Uint8List wavData = _generateWav(freq, durationSec);

    final player = AudioPlayer();
    await player.play(BytesSource(wavData));

    // 等待音符播放完毕
    await Future.delayed(Duration(milliseconds: (durationSec * 1000).round()));
    await player.dispose();
  }

  /// 停止所有播放
  Future<void> stopAll() async {
    for (final player in _players.values) {
      await player.stop();
      await player.dispose();
    }
    _players.clear();
  }
}

// ==================== 数据库 ====================
class DBHelper {
  static final DBHelper instance = DBHelper._();
  static Database? _db;
  DBHelper._();

  Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'jianpuyi.db');
    return await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE scores (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT DEFAULT '未命名乐谱',
          image_path TEXT,
          notes TEXT,
          key_sig TEXT DEFAULT '1=C',
          tempo INTEGER DEFAULT 85,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          is_favorite INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE settings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          instrument TEXT DEFAULT 'Piano',
          theme TEXT DEFAULT 'Dark'
        )
      ''');
      await db.insert('settings', {'instrument': 'Piano', 'theme': 'Dark'});
    });
  }

  Future<int> saveScore(String title, String imagePath, String notes, String key, int tempo) async {
    final db = await database;
    return await db.insert('scores', {
      'title': title,
      'image_path': imagePath,
      'notes': notes,
      'key_sig': key,
      'tempo': tempo,
    });
  }

  Future<List<Map<String, dynamic>>> getAllScores() async {
    final db = await database;
    return await db.query('scores', orderBy: 'created_at DESC');
  }

  Future<void> toggleFavorite(int id, bool fav) async {
    final db = await database;
    await db.update('scores', {'is_favorite': fav ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteScore(int id) async {
    final db = await database;
    await db.delete('scores', where: 'id = ?', whereArgs: [id]);
  }
}

// ==================== 扫描页（首页） ====================
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final ImagePicker _picker = ImagePicker();
  final DBHelper _db = DBHelper.instance;
  List<Map<String, dynamic>> _scores = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScores();
  }

  Future<void> _loadScores() async {
    setState(() => _isLoading = true);
    _scores = await _db.getAllScores();
    setState(() => _isLoading = false);
  }

  Future<void> _scanFromCamera() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo != null) await _processImage(photo.path);
  }

  Future<void> _scanFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image != null) await _processImage(image.path);
  }

  Future<void> _processImage(String imagePath) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF00E676)),
                SizedBox(height: 16),
                Text('正在识别简谱...', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));

    // 模拟识别结果（小星星）
    final mockResult = {
      'notes': ['1', '1', '5', '5', '6', '6', '5', '-', '4', '4', '3', '3', '2', '2', '1', '-'],
      'key': 'C Major',
      'tempo': 85,
    };

    final int scoreId = await _db.saveScore(
      '小星星',
      imagePath,
      jsonEncode(mockResult['notes']),
      mockResult['key'] as String,
      mockResult['tempo'] as int,
    );

    Navigator.pop(context);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultPage(scoreId: scoreId, result: mockResult)),
    ).then((_) => _loadScores());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('简谱译', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('JianPuYi v1.2 · AI Music Scanner', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white54, size: 28),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage())).then((_) => _loadScores()),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // 扫描框
            GestureDetector(
              onTap: _scanFromCamera,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E676), width: 2),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF00E676).withOpacity(0.15), blurRadius: 30, spreadRadius: 5),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(top: 12, left: 12, child: _cornerDecor()),
                    Positioned(top: 12, right: 12, child: Transform.flip(flipX: true, child: _cornerDecor())),
                    Positioned(bottom: 12, left: 12, child: Transform.flip(flipY: true, child: _cornerDecor())),
                    Positioned(bottom: 12, right: 12, child: Transform.flip(flipX: true, flipY: true, child: _cornerDecor())),
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.music_note, size: 56, color: Color(0xFF00E676)),
                          SizedBox(height: 16),
                          Text('点击拍照识别简谱', style: TextStyle(color: Colors.white70, fontSize: 16)),
                          SizedBox(height: 6),
                          Text('请将简谱对准方框', style: TextStyle(color: Colors.white30, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            TextButton.icon(
              onPressed: _scanFromGallery,
              icon: const Icon(Icons.photo_library, color: Color(0xFF00E676)),
              label: const Text('从相册选择', style: TextStyle(color: Color(0xFF00E676))),
            ),

            const SizedBox(height: 32),

            // 最近记录
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('最近识别', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _scores.isEmpty
                              ? Center(child: Text('暂无记录，拍照开始识别', style: TextStyle(color: Colors.white.withOpacity(0.3))))
                              : ListView.builder(
                                  itemCount: _scores.length > 5 ? 5 : _scores.length,
                                  itemBuilder: (_, i) => _buildScoreItem(_scores[i]),
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cornerDecor() {
    return Container(
      width: 24, height: 24,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF00E676), width: 3),
          left: BorderSide(color: Color(0xFF00E676), width: 3),
        ),
      ),
    );
  }

  Widget _buildScoreItem(Map<String, dynamic> score) {
    return Card(
      color: const Color(0xFF161B22),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.music_note, color: Color(0xFF00E676)),
        ),
        title: Text(score['title'] ?? '未命名', style: const TextStyle(color: Colors.white)),
        subtitle: Text('${score['key_sig']} · ${score['tempo']} BPM', style: const TextStyle(color: Colors.white38)),
        trailing: Icon(
          score['is_favorite'] == 1 ? Icons.favorite : Icons.favorite_border,
          color: score['is_favorite'] == 1 ? Colors.redAccent : Colors.white24,
        ),
        onTap: () {
          final notes = jsonDecode(score['notes'] ?? '[]');
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ResultPage(
              scoreId: score['id'],
              result: {'notes': notes, 'key': score['key_sig'], 'tempo': score['tempo']},
            )),
          ).then((_) => _loadScores());
        },
      ),
    );
  }
}

// ==================== 识别结果页（带真实音频） ====================
class ResultPage extends StatefulWidget {
  final int scoreId;
  final Map<String, dynamic> result;
  const ResultPage({super.key, required this.scoreId, required this.result});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final NotePlayer _notePlayer = NotePlayer.instance;
  bool _isPlaying = false;
  int _currentIndex = -1;
  double _speedMultiplier = 1.0;

  Future<void> _playNotes() async {
    if (_isPlaying) {
      setState(() { _isPlaying = false; _currentIndex = -1; });
      return;
    }

    final notes = widget.result['notes'] as List;
    final tempo = widget.result['tempo'] as int;
    // 每拍时长（秒）
    final double beatDuration = 60.0 / tempo / _speedMultiplier;

    setState(() => _isPlaying = true);

    for (int i = 0; i < notes.length && _isPlaying; i++) {
      setState(() => _currentIndex = i);

      final String note = notes[i].toString();

      if (note == '-' || note == '0') {
        // 休止符
        await Future.delayed(Duration(milliseconds: (beatDuration * 1000).round()));
      } else {
        // 播放真实音符
        await _notePlayer.playNote(note, durationSec: beatDuration * 0.9);
      }
    }

    setState(() { _isPlaying = false; _currentIndex = -1; });
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.result['notes'] as List;
    final key = widget.result['key'] as String;
    final tempo = widget.result['tempo'] as int;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('识别结果'),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // 乐谱信息卡片
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _infoChip('调号', key),
                _infoChip('速度', '$tempo BPM'),
                _infoChip('音符', '${notes.length} 个'),
              ],
            ),
          ),

          // 速度控制
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.speed, color: Colors.white38, size: 20),
                const SizedBox(width: 8),
                const Text('播放速度', style: TextStyle(color: Colors.white54, fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: _speedMultiplier,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    activeColor: const Color(0xFF00E676),
                    label: '${_speedMultiplier.toStringAsFixed(1)}x',
                    onChanged: (v) => setState(() => _speedMultiplier = v),
                  ),
                ),
                Text('${_speedMultiplier.toStringAsFixed(1)}x',
                    style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 音符显示区
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('音符序列', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      if (_isPlaying)
                        Text('${_currentIndex + 1}/${notes.length}',
                            style: const TextStyle(color: Color(0xFF00E676), fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: notes.asMap().entries.map((e) {
                          final isCurrent = e.key == _currentIndex;
                          final isRest = e.value == '-' || e.value == '0';
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 48, height: 56,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF00E676)
                                  : isRest
                                      ? const Color(0xFF21262D)
                                      : const Color(0xFF0D1117),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCurrent ? const Color(0xFF00E676) : const Color(0xFF30363D),
                                width: isCurrent ? 2 : 1,
                              ),
                              boxShadow: isCurrent
                                  ? [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 12)]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                isRest ? '-' : e.value.toString(),
                                style: TextStyle(
                                  color: isCurrent ? Colors.black : Colors.white70,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 播放控制栏
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 重置按钮
                IconButton(
                  icon: const Icon(Icons.replay, color: Colors.white54, size: 28),
                  onPressed: () {
                    setState(() { _isPlaying = false; _currentIndex = -1; });
                  },
                ),
                // 播放/停止
                GestureDetector(
                  onTap: _playNotes,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 20, spreadRadius: 4),
                      ],
                    ),
                    child: Icon(
                      _isPlaying ? Icons.stop : Icons.play_arrow,
                      size: 36, color: Colors.black,
                    ),
                  ),
                ),
                // 虚拟钢琴按钮
                IconButton(
                  icon: const Icon(Icons.piano, color: Colors.white54, size: 28),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const VirtualPianoPage()));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Color(0xFF00E676), fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ==================== 虚拟钢琴页 ====================
class VirtualPianoPage extends StatelessWidget {
  const VirtualPianoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final notePlayer = NotePlayer.instance;
    final notes = ['1', '2', '3', '4', '5', '6', '7'];
    final noteNames = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'];

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('虚拟钢琴'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          const Text('点击琴键试听音符', style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 40),

          // 钢琴键
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: notes.asMap().entries.map((e) {
                  final colors = [
                    Colors.red, Colors.orange, Colors.yellow,
                    Colors.green, Colors.cyan, Colors.blue, Colors.purple,
                  ];
                  return Expanded(
                    child: GestureDetector(
                      onTapDown: (_) => notePlayer.playNote(e.value, durationSec: 0.8),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [colors[e.key].withOpacity(0.8), colors[e.key].withOpacity(0.3)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors[e.key].withOpacity(0.5)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(noteNames[e.key], style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ==================== 历史记录页 ====================
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final DBHelper _db = DBHelper.instance;
  List<Map<String, dynamic>> _scores = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _scores = await _db.getAllScores();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('历史记录'),
      ),
      body: _scores.isEmpty
          ? const Center(child: Text('暂无记录', style: TextStyle(color: Colors.white38)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _scores.length,
              itemBuilder: (_, i) {
                final s = _scores[i];
                return Dismissible(
                  key: Key(s['id'].toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await _db.deleteScore(s['id']);
                    _load();
                  },
                  child: Card(
                    color: const Color(0xFF161B22),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.music_note, color: Color(0xFF00E676)),
                      ),
                      title: Text(s['title'] ?? '未命名', style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${s['key_sig']} · ${s['tempo']} BPM', style: const TextStyle(color: Colors.white38)),
                      trailing: IconButton(
                        icon: Icon(
                          s['is_favorite'] == 1 ? Icons.favorite : Icons.favorite_border,
                          color: s['is_favorite'] == 1 ? Colors.redAccent : Colors.white24,
                        ),
                        onPressed: () async {
                          await _db.toggleFavorite(s['id'], s['is_favorite'] != 1);
                          _load();
                        },
                      ),
                      onTap: () {
                        final notes = jsonDecode(s['notes'] ?? '[]');
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ResultPage(
                            scoreId: s['id'],
                            result: {'notes': notes, 'key': s['key_sig'], 'tempo': s['tempo']},
                          )),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
