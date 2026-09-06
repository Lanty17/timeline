import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FontFeature;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// 今日日程时间线 · 无边框 + 右键设置版
//  - 白色底色，单独一个时间轴（靠右，时间自上而下，紧贴右边框）
//  - 右侧一条四色粗竖线（蓝 金 橙 红，无间隔合并）
//  - 小时数字标签右对齐、贴靠粗线左侧
//  - 日程块统一柔和蓝灰色，Now 红色指针每秒移动，且绘制在最上层覆盖粗线
//  - 窗口无边框（隐藏最小化/最大化/关闭标题栏）；
//    右键页面任意处可进入设置页，编辑任务名称与起止时间（可覆盖）
// 配色：蓝 #21467A / 金 #DBA972 / 橙 #D45814 / 红 #C71F2D
// ============================================================================

const Color kBlue = Color(0xFF21467A);   // 剧场蓝
const Color kGold = Color(0xFFDBA972);   // 金秋岁月
const Color kOrange = Color(0xFFD45814); // 波斯橙
const Color kRed = Color(0xFFC71F2D);    // 高危险红
const Color kTask = Color(0xFF7A94BC);   // 日程块统一色（柔和蓝灰）

void main() => runApp(const TimelineApp());

class TimelineApp extends StatelessWidget {
  const TimelineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '今日日程时间线',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const TimelineScreen(),
    );
  }
}

/// 日程数据模型
class Task {
  final DateTime begin;
  final DateTime end;
  final String title;
  final String detail; // 任务详情（可选）
  const Task(this.begin, this.end, this.title, {this.detail = ''});
}

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const MethodChannel _moveChannel = MethodChannel('timeline/move_window');

  late DateTime _now;
  Timer? _timer;

  late DateTime _start; // 00:00
  late DateTime _end;   // 24:00
  late List<Task> _tasks;
  bool _top = false; // 窗口置顶

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _start = _at(_now, 0);
    _end = _at(_now, 24);
    _tasks = _defaultTasks(_now);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
    _loadTasks();
    _loadRange();
    _loadTop();
    _moveChannel.invokeMethod('set_topmost', _top);
    // 探测移动通道是否注册成功
    _moveChannel.invokeMethod('ping').catchError((e) => _log('ping_err: \$e'));
  }

  List<Task> _defaultTasks(DateTime ref) => [
        Task(_at(ref, 9, 0), _at(ref, 10, 30), '早会'),
        Task(_at(ref, 11, 0), _at(ref, 12, 30), '需求评审'),
        Task(_at(ref, 14, 0), _at(ref, 16, 0), '编码冲刺'),
        Task(_at(ref, 16, 30), _at(ref, 17, 45), '代码走查'),
      ];

  DateTime _at(DateTime ref, int hour, [int minute = 0]) =>
      DateTime(ref.year, ref.month, ref.day, hour, minute);

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // 范围结束时刻：次日零点以 24:00 显示
  String _hmRangeEnd(DateTime t) =>
      (t.minute == 0 && t.hour == 0 && t.isAfter(_start)) ? '24:00' : _hm(t);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const String _taskFile = r'D:\Downloads\timeline\tasks.json';
  static const String _rangeFile = r'D:\Downloads\timeline\range.json';
  static const String _topFile = r'D:\Downloads\timeline\top.json';

  void _loadTasks() {
    try {
      final f = File(_taskFile);
      if (!f.existsSync()) return;
      final list = jsonDecode(f.readAsStringSync()) as List;
      final loaded = <Task>[
        for (final m in list)
          if (m is Map)
            Task(DateTime.parse(m['b'] as String),
                DateTime.parse(m['e'] as String), m['t'] as String,
                detail: m['d'] as String? ?? ''),
      ];
      if (loaded.isNotEmpty) _tasks = loaded;
    } catch (_) {}
  }

  void _saveTasks(List<Task> ts) {
    try {
      File(_taskFile).writeAsStringSync(jsonEncode([
        for (final t in ts)
          {
            'b': t.begin.toIso8601String(),
            'e': t.end.toIso8601String(),
            't': t.title,
            'd': t.detail,
          }
      ]));
    } catch (_) {}
  }

  void _saveRange(DateTime s, DateTime e) {
    try {
      File(_rangeFile).writeAsStringSync(jsonEncode(
          {'s': s.toIso8601String(), 'e': e.toIso8601String()}));
    } catch (_) {}
  }

  void _loadRange() {
    try {
      final f = File(_rangeFile);
      if (!f.existsSync()) return;
      final m = jsonDecode(f.readAsStringSync());
      if (m is Map && m['s'] is String && m['e'] is String) {
        _start = DateTime.parse(m['s'] as String);
        _end = DateTime.parse(m['e'] as String);
      }
    } catch (_) {}
  }

  void _saveTop(bool v) {
    try {
      File(_topFile).writeAsStringSync(jsonEncode(v));
    } catch (_) {}
  }

  void _loadTop() {
    try {
      final f = File(_topFile);
      if (!f.existsSync()) return;
      final v = jsonDecode(f.readAsStringSync());
      if (v is bool) _top = v;
    } catch (_) {}
  }

  void _log(String s) {
    try {
      File(r'D:\Downloads\timeline\move.debug.log')
          .writeAsStringSync('\$s\n', mode: FileMode.append);
    } catch (_) {}
  }

  void _onDragStart(PointerDownEvent e) {
    // Delegate to the native window move loop (same as window_manager),
    // which is smooth and free of flicker.
    if ((e.buttons & kPrimaryButton) != 0) {
      try {
        _moveChannel.invokeMethod('startDrag');
      } catch (_) {}
    }
  }

  // 打开设置页；设置改动通过 onChanged 即时同步并自动保存
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          initial: List.of(_tasks),
          rangeStartText: _hm(_start),
          rangeEndText: _hmRangeEnd(_end),
          topmost: _top,
          onChanged: (ts) {
            if (!mounted) return;
            setState(() => _tasks = ts);
            _saveTasks(ts);
          },
          onRangeChanged: (s, en) {
            if (!mounted) return;
            setState(() {
              _start = s;
              _end = en;
            });
            _saveRange(s, en);
          },
          onTopmostChanged: (v) {
            if (!mounted) return;
            _top = v;
            _saveTop(v);
            try {
              _moveChannel.invokeMethod('set_topmost', v);
            } catch (_) {}
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Horizontal starfield background covering the whole page.
          Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: RotatedBox(
                quarterTurns: 1,
                child: Image.asset(
                  'assets/Starfield_Wallpaper_Light.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          SafeArea(
        child: Listener(
          onPointerDown: _onDragStart,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Right-click opens settings; left-button drag moves the window.
          onSecondaryTapUp: (_) => _openSettings(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(3, 4, 2, 10),
                  child: CustomPaint(
                    painter: TimelinePainter(
                      start: _start,
                      end: _end,
                      now: _now,
                      tasks: _tasks,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
            ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white.withValues(alpha: 0.95),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
      child: Row(
        children: [
          const Text('今日日程',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: kBlue)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: kBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_now.year}-${_two(_now.month)}-${_two(_now.day)}',
              style: const TextStyle(fontSize: 13, color: kBlue),
            ),
          ),
          const Spacer(),
          Text(
            '当前 ${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
            style: const TextStyle(
                fontSize: 16,
                color: kRed,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    ),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}

// ============================================================================
// 设置页：编辑任务名称与起止时间（可覆盖），UI 风格与主界面一致
// ============================================================================
class SettingsPage extends StatefulWidget {
  final List<Task> initial;
  final ValueChanged<List<Task>> onChanged;
  final String rangeStartText;
  final String rangeEndText;
  final void Function(DateTime s, DateTime e)? onRangeChanged;
  final bool topmost;
  final ValueChanged<bool>? onTopmostChanged;
  const SettingsPage(
      {super.key,
      required this.initial,
      required this.onChanged,
      required this.rangeStartText,
      required this.rangeEndText,
      this.onRangeChanged,
      required this.topmost,
      this.onTopmostChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final List<_TaskEdit> _edits = [];
  late DateTime _day;
  late final TextEditingController _rs;
  late final TextEditingController _re;
  late bool _top;


  @override
  void initState() {
    super.initState();
    _day = widget.initial.isNotEmpty
        ? widget.initial.first.begin
        : DateTime.now();
    _rs = TextEditingController(text: widget.rangeStartText);
    _re = TextEditingController(text: widget.rangeEndText);
    _top = widget.topmost;
    for (var i = 0; i < widget.initial.length; i++) {
      final t = widget.initial[i];
      _edits.add(_TaskEdit(
        title: TextEditingController(text: t.title),
        detail: TextEditingController(text: t.detail),
        begin: TextEditingController(text: _hm(t.begin)),
        end: TextEditingController(text: _hm(t.end)),
      ));
    }
    if (_edits.isEmpty) {
      _edits.add(_TaskEdit(
        title: TextEditingController(text: '新任务'),
        detail: TextEditingController(text: ''),
        begin: TextEditingController(text: _hm(_at(DateTime.now(), 9))),
        end: TextEditingController(text: _hm(_at(DateTime.now(), 10))),
      ));
    }
  }

  DateTime _at(DateTime ref, int hour, [int minute = 0]) =>
      DateTime(ref.year, ref.month, ref.day, hour, minute);

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _rs.dispose();
    _re.dispose();
    for (final e in _edits) {
      e.title.dispose();
      e.detail.dispose();
      e.begin.dispose();
      e.end.dispose();
    }
    super.dispose();
  }

  // 新增一条任务（默认时段，随后可在输入框覆盖）
  void _addTask() {
    final n = _edits.length + 1;
    final beginH = 9 + (n - 1) % 8;
    _edits.add(_TaskEdit(
      title: TextEditingController(text: '新任务${n}'),
      detail: TextEditingController(text: ''),
      begin: TextEditingController(text: _hm(_at(_day, beginH))),
      end: TextEditingController(text: _hm(_at(_day, beginH + 1))),
    ));
    setState(() {});
  }

  // 删除一条任务，并即时同步保存
  void _deleteTask(int i) {
    setState(() => _edits.removeAt(i));
    _emit();
  }

  // 解析 "HH:MM"，失败返回 null
  DateTime? _parse(String s, DateTime base) {
    final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return DateTime(base.year, base.month, base.day, h, min);
  }
  void _emit() {
    final List<Task> out = [];
    for (final e in _edits) {
      final title = e.title.text.trim().isEmpty ? '未命名' : e.title.text.trim();
      final b = _parse(e.begin.text, _day);
      final en = _parse(e.end.text, _day);
      if (b == null || en == null) return; // 尚有未完成的输入，暂不保存
      final b2 = en.isAfter(b) ? b : en;
      final e2 = en.isAfter(b) ? en : b;
      out.add(Task(b2, e2, title, detail: e.detail.text.trim()));
    }
    widget.onChanged(out);
  }

  // 单独同步时间线显示范围，避免因任务未填全而不触发保存
  void _emitRange() {
    final rs = _parse(_rs.text, _day);
    final re = _parseRangeEnd(_re.text, _day);
    if (rs != null && re != null && re.isAfter(rs)) {
      widget.onRangeChanged?.call(rs, re);
    }
  }

  // 切换窗口置顶
  void _setTopmost(bool v) {
    setState(() => _top = v);
    widget.onTopmostChanged?.call(v);
  }

  // 解析范围结束时刻，允许 24:00（次日零点）
  DateTime? _parseRangeEnd(String s, DateTime base) {
    final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h < 0 || h > 24 || min < 0 || min > 59) return null;
    return DateTime(base.year, base.month, base.day, h, min);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (_) => Navigator.of(context).maybePop(),
      child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _startDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _colorStrip(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: _pageHeader(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  _sectionTitle('通用设置'),
                  const SizedBox(height: 8),
                  _generalCard(),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: _sectionTitle('今日任务')),
                      _addTaskButton(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_edits.isEmpty)
                    _emptyTasks()
                  else
                    ...List.generate(_edits.length, (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _taskCard(context, i),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  static const MethodChannel _mv = MethodChannel('timeline/move_window');

  void _startDrag(PointerDownEvent e) {
    if ((e.buttons & kPrimaryButton) != 0) {
      try {
        _mv.invokeMethod('startDrag');
      } catch (_) {}
    }
  }

  Widget _colorStrip() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _startDrag,
      child: const SizedBox(
        height: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ColoredBox(color: kBlue)),
            Expanded(child: ColoredBox(color: kGold)),
            Expanded(child: ColoredBox(color: kOrange)),
            Expanded(child: ColoredBox(color: kRed)),
          ],
        ),
      ),
    );
  }

  Widget _pageHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('设置',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: kBlue)),
        SizedBox(height: 6),
        Text('管理时间线显示范围与今日任务，右键返回',
            style: TextStyle(fontSize: 12, color: Color(0xFF7C86A0))),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
            width: 6,
            height: 16,
            decoration: BoxDecoration(
                color: kBlue, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: kBlue)),
      ],
    );
  }

  Widget _generalCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E9F1)),
        boxShadow: [
          BoxShadow(
              color: kBlue.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          _generalRow(
            icon: Icons.timeline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('时间线显示范围',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF24324E))),
                const SizedBox(height: 10),
                Row(children: [
                  _timeField(_rs, '起始', onChanged: _emitRange),
                  const SizedBox(width: 12),
                  _timeField(_re, '结束', onChanged: _emitRange),
                ]),
              ],
            ),
          ),
          const Divider(
              color: Color(0xFFEEF1F6),
              height: 1,
              indent: 14,
              endIndent: 14,
              thickness: 1),
          _generalRow(
            icon: Icons.push_pin,
            child: Row(
              children: [
                const Expanded(
                  child: Text('窗口置顶',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF24324E))),
                ),
                Switch(value: _top, onChanged: _setTopmost),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _generalRow({required IconData icon, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: kBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: kBlue),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _addTaskButton() {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      onPressed: _addTask,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('新增任务', style: TextStyle(fontSize: 13)),
    );
  }

  Widget _emptyTasks() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E9F1)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_note, size: 40, color: Color(0xFFB9C4D6)),
          SizedBox(height: 10),
          Text('还没有任务，点右上角新增一条',
              style: TextStyle(fontSize: 13, color: Color(0xFF7C86A0))),
        ],
      ),
    );
  }
  Widget _taskCard(BuildContext context, int i) {
    final e = _edits[i];
    final color = kTask; // 色卡统一用一种颜色
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E9F1)),
        boxShadow: [
          BoxShadow(
              color: kBlue.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 8, height: 22, decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            const Text('任务',
                style: TextStyle(fontSize: 12, color: Color(0xFF7C86A0))),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () => _deleteTask(i),
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: Color(0xFFC47682)),
              tooltip: '删除',
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: e.title,
            onChanged: (_) => _emit(),
            style: const TextStyle(fontSize: 15, color: Color(0xFF24324E)),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '输入任务名称',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8))),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: e.detail,
            onChanged: (_) => _emit(),
            minLines: 2,
            maxLines: 3,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7690)),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '任务详情（可选）',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8))),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _timeField(e.begin, '开始'),
            const SizedBox(width: 12),
            _timeField(e.end, '结束'),
          ]),
        ],
      ),
    );
  }

  Widget _timeField(TextEditingController controller, String label,
      {VoidCallback? onChanged}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7C86A0))),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onChanged: (_) => (onChanged ?? _emit)(),
            keyboardType: TextInputType.datetime,
            style: const TextStyle(fontSize: 15, color: Color(0xFF24324E)),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'HH:MM',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8))),
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置页单条任务的编辑控件容器
class _TaskEdit {
  final TextEditingController title;
  final TextEditingController detail;
  final TextEditingController begin;
  final TextEditingController end;
  _TaskEdit(
      {required this.title, required this.detail, required this.begin, required this.end});
}

// ============================================================================
// 时间轴画家
// ============================================================================
class TimelinePainter extends CustomPainter {
  final DateTime start, end, now;
  final List<Task> tasks;

  const TimelinePainter({
    required this.start,
    required this.end,
    required this.now,
    required this.tasks,
  });

  // 时间 → 像素（纵轴，自上而下）
  double _toY(DateTime t, double bodyTop, double bodyH) {
    final total = end.difference(start).inMinutes;
    return bodyTop + t.difference(start).inMinutes / total * bodyH;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double topPad = 18;
    const double bottomPad = 18;
    const double leftStart = 10; // 日程块起始（左标签区右侧）

    const int decoCount = 4;
    const double decoLineW = 10;    // 每条装饰竖线宽（无间距 → 拼成一条粗线）
    const double decoGap = 0;       // 四条靠紧，间距为 0
    const double rightEdgePad = 3;  // 最右留白（贴边）
    const double decoTotalW = decoCount * decoLineW + (decoCount - 1) * decoGap;
    const double labelGap = 12;     // 标签与粗线间距

    final bodyTop = topPad;
    final bodyBottom = size.height - bottomPad;
    final bodyH = bodyBottom - bodyTop;

    final decoLeftX = size.width - rightEdgePad - decoTotalW; // 粗线左边缘
    final laneGap = 44;  // 泳道左侧到粗线左侧之间留出标签+泳道间隙
    final laneRight = decoLeftX - labelGap - laneGap;
    const double barW = 14; // 时间泳道宽度
    final laneLeft = laneRight - barW;

    // --- 小时刻度网格线与时间标签（标签右对齐、贴靠粗线）---
    final grid = Paint()
      ..color = const Color(0xFFDCE3EE)
      ..strokeWidth = 1;
    // 刻度线：范围 start→end 内每个整点 + 起止边界（不再固定 0-24）
    String _h(DateTime t) => t.minute == 0
        ? '${t.hour}:00'
        : '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
    void _drawLine(double y) {
      canvas.drawLine(
          Offset(leftStart, y), Offset(size.width - rightEdgePad, y), grid);
    }
    void _drawLabel(DateTime t, double y) {
      final tp = TextPainter(
        text: TextSpan(text: _h(t),
            style: const TextStyle(fontSize: 12, color: Color(0xFF3A4A6B))),
        textDirection: TextDirection.ltr,
      )..layout();
      // 数字右对齐，紧贴粗线左侧
      tp.paint(canvas, Offset(decoLeftX - labelGap - tp.width, y - tp.height / 2));
    }
    _drawLine(_toY(start, bodyTop, bodyH));
    _drawLabel(start, _toY(start, bodyTop, bodyH));
    final endHour = (end.hour == 0 && end != start) ? 24 : end.hour;
    for (var h = start.hour + 1; h <= endHour; h++) {
      final tick = DateTime(start.year, start.month, start.day, h, 0);
      if (tick == end) continue; // 结束整点由边界线表达
      if (!tick.isBefore(end) && tick != end) continue;
      final y = _toY(tick, bodyTop, bodyH);
      _drawLine(y);
      _drawLabel(tick, y);
    }
    final endY = _toY(end, bodyTop, bodyH);
    _drawLine(endY);
    final endLabel = (end.hour == 0 && end.minute == 0) ? '24:00' : _h(end);
    final tpEnd = TextPainter(
      text: TextSpan(text: endLabel,
          style: const TextStyle(fontSize: 12, color: Color(0xFF3A4A6B))),
      textDirection: TextDirection.ltr,
    )..layout();
    tpEnd.paint(
        canvas, Offset(decoLeftX - labelGap - tpEnd.width, endY - tpEnd.height / 2));

    // --- 时间泳道底带 ---
    final lane = RRect.fromRectAndRadius(
      Rect.fromLTWH(laneLeft, bodyTop, barW, bodyH),
      const Radius.circular(6),
    );
    canvas.drawRRect(lane, Paint()..color = const Color(0xFFEEF2F8));

    // --- 日程块（统一 kTask 色）---
    for (final t in tasks) {
      final y0 = limit(_toY(t.begin, bodyTop, bodyH), bodyTop, bodyBottom);
      final y1 = limit(_toY(t.end, bodyTop, bodyH), bodyTop, bodyBottom);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            leftStart, y0, laneRight - leftStart, (y1 - y0 - 3).clamp(6, bodyH)),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = kTask.withValues(alpha: 0.85));
      if (y1 - y0 > 22) {
        final maxW = laneRight - leftStart - 10;
        final tp = TextPainter(
          text: TextSpan(text: t.title,
              style: const TextStyle(
                  fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxW);
        tp.paint(canvas, Offset(leftStart + 6, y0 + 3));
        // 任务详情（块高度足够时显示在名称下方）
        if (y1 - y0 > 44 && t.detail.isNotEmpty) {
          final lines = ((y1 - y0 - 6 - tp.height - 4) / 15).clamp(1, 3).toInt();
          final td = TextPainter(
            text: TextSpan(text: t.detail,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
            maxLines: lines,
            ellipsis: '…',
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: maxW);
          td.paint(canvas, Offset(leftStart + 6, y0 + 3 + tp.height + 3));
        }
      }
    }

    // --- 四条竖线靠紧合并成一条粗线：从左到右 蓝→金→橙→红 ---
    const decoColors = [kBlue, kGold, kOrange, kRed];
    for (var i = 0; i < decoCount; i++) {
      final x = decoLeftX + i * (decoLineW + decoGap);
      canvas.drawLine(Offset(x, bodyTop), Offset(x, bodyBottom),
          Paint()..color = decoColors[i]..strokeWidth = decoLineW
            ..strokeCap = StrokeCap.round);
    }

    // --- Now 当前时间指针（最后绘制 → 在最上层，覆盖右侧粗线）---
    final nowY = limit(_toY(now, bodyTop, bodyH), bodyTop, bodyBottom);
    canvas.drawLine(Offset(leftStart, nowY),
        Offset(size.width - rightEdgePad, nowY),
        Paint()..color = kRed..strokeWidth = 2);
    canvas.drawCircle(Offset(leftStart - 1, nowY), 4,
        Paint()..color = kRed);
  }

  double limit(double v, double lo, double hi) => v.clamp(lo, hi).toDouble();

  @override
  bool shouldRepaint(TimelinePainter old) =>
      old.now != now ||
      old.start != start ||
      old.end != end ||
      old.tasks != tasks;
}