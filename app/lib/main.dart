import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const JianPuYiApp());
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
    // 显示加载动画
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

    Navigator.pop(context); // 关闭加载

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
                      Text('JianPuYi · AI Music Scanner', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white54, size: 28),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryPage())).then((_) => _loadScores()),
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
                    // 四角装饰
                    Positioned(top: 12, left: 12, child: _cornerDecor()),
                    Positioned(top: 12, right: 12, child: Transform.flip(flipX: true, child: _cornerDecor())),
                    Positioned(bottom: 12, left: 12, child: Transform.flip(flipY: true, child: _cornerDecor())),
                    Positioned(bottom: 12, right: 12, child: Transform.flip(flipX: true, flipY: true, child: _cornerDecor())),
                    // 中心内容
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

            // 相册按钮
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

// ==================== 识别结果页 ====================
class ResultPage extends StatefulWidget {
  final int scoreId;
  final Map<String, dynamic> result;
  const ResultPage({super.key, required this.scoreId, required this.result});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  bool _isPlaying = false;
  int _currentIndex = -1;

  Future<void> _playNotes() async {
    if (_isPlaying) {
      setState(() { _isPlaying = false; _currentIndex = -1; });
      return;
    }

    final notes = widget.result['notes'] as List;
    final tempo = widget.result['tempo'] as int;
    final durationMs = (60000 / tempo).round();

    setState(() => _isPlaying = true);

    for (int i = 0; i < notes.length && _isPlaying; i++) {
      setState(() => _currentIndex = i);
      await Future.delayed(Duration(milliseconds: durationMs));
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
                  const Text('音符序列', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
                            duration: const Duration(milliseconds: 200),
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

          // 播放控制
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.large(
                  onPressed: _playNotes,
                  backgroundColor: const Color(0xFF00E676),
                  child: Icon(
                    _isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 40,
                    color: Colors.black,
                  ),
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
