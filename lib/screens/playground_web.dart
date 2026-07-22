// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _htmlCtrl = TextEditingController(text: _defaultHtml);
  final _cssCtrl = TextEditingController(text: _defaultCss);
  final _jsCtrl = TextEditingController(text: _defaultJs);
  final _mdCtrl = TextEditingController(text: _defaultMd);

  late final String _viewType;
  late final html.IFrameElement _iframe;
  int _activeTab = 0;
  bool _ready = false;

  // Colors
  static const _bg = Color(0xFF0A0A14);
  static const _surface = Color(0xFF12121E);
  static const _surfaceLight = Color(0xFF1A1A2E);
  static const _border = Color(0xFF252538);
  static const _textDim = Color(0xFF5A5A78);
  static const _textMuted = Color(0xFF8B8FA7);
  static const _accent = Color(0xFF7C3AED);
  static const _green = Color(0xFF22C55E);

  static const _defaultHtml = '''<div class="card">
  <div class="glow"></div>
  <h1>Hello, AskCore! 👋</h1>
  <p>Edit HTML, CSS & JS — lalu tekan <strong>▶ Run</strong></p>
  <button id="btn" onclick="">Click Me</button>
  <div id="output"></div>
</div>''';

  static const _defaultCss =
      '''* { margin: 0; padding: 0; box-sizing: border-box; }

body {
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  background: #0a0a14;
  color: #e4e4ef;
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  overflow: hidden;
}

.card {
  position: relative;
  background: rgba(255,255,255,0.03);
  backdrop-filter: blur(40px);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 24px;
  padding: 3rem 2.5rem;
  text-align: center;
  max-width: 460px;
  width: 90%;
}

.glow {
  position: absolute;
  top: -60px; left: 50%;
  transform: translateX(-50%);
  width: 200px; height: 200px;
  background: radial-gradient(circle, rgba(124,58,237,0.3), transparent 70%);
  pointer-events: none;
}

h1 {
  font-size: 2.2rem;
  font-weight: 800;
  background: linear-gradient(135deg, #fff, #a78bfa);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 0.5rem;
}

p { color: #8b8fa7; margin-bottom: 2rem; line-height: 1.7; }

button {
  background: linear-gradient(135deg, #7C3AED, #9333EA);
  color: white;
  border: none;
  padding: 14px 40px;
  border-radius: 14px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  position: relative;
  overflow: hidden;
}

button::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(135deg, transparent, rgba(255,255,255,0.1));
  opacity: 0;
  transition: opacity 0.3s;
}

button:hover {
  transform: translateY(-3px) scale(1.02);
  box-shadow: 0 12px 35px rgba(124, 58, 237, 0.45);
}
button:hover::after { opacity: 1; }
button:active { transform: translateY(-1px) scale(0.98); }

#output {
  margin-top: 1.5rem;
  font-size: 1.3rem;
  font-weight: 600;
  min-height: 1.5em;
  background: linear-gradient(135deg, #a78bfa, #7c3aed);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}''';

  static const _defaultJs = '''let count = 0;
const btn = document.getElementById('btn');
const out = document.getElementById('output');

btn.addEventListener('click', () => {
  count++;
  out.textContent = `Clicked \${count} time\${count > 1 ? 's' : ''}! 🎉`;
  
  // Pulse animation
  btn.style.transform = 'scale(0.93)';
  setTimeout(() => btn.style.transform = '', 200);
});''';

  static const _defaultMd = '''# AskCore Markdown

## Features
- **Bold text** and *italic text*
- Inline code: `console.log("hello")`

```javascript
function greet(name) {
  return `Hello, \${name}!`;
}
```

| Feature | Status |
|---------|--------|
| Syntax Highlighting | ✅ |
| Live Preview | ✅ |

> "Code is poetry."

---
*Made with ❤️ by AskCore*''';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _activeTab = _tabController.index);
      }
    });
    _initIframe();
  }

  void _initIframe() {
    _viewType = 'pg-${DateTime.now().millisecondsSinceEpoch}';
    _iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'scripts'
      ..setAttribute('sandbox', 'allow-scripts allow-same-origin');

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int id) => _iframe,
    );

    setState(() => _ready = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _run();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _htmlCtrl.dispose();
    _cssCtrl.dispose();
    _jsCtrl.dispose();
    _mdCtrl.dispose();
    super.dispose();
  }

  void _run() {
    _activeTab == 3 ? _runMd() : _runWeb();
  }

  void _runWeb() {
    _iframe.srcdoc =
        '''<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<style>${_cssCtrl.text}</style></head>
<body>${_htmlCtrl.text}
<script>${_jsCtrl.text}</script></body></html>''';
  }

  void _runMd() {
    String h = _mdCtrl.text;
    h = h.replaceAllMapped(
      RegExp(r'```\w*\n([\s\S]*?)```'),
      (m) => '<pre><code>${_esc(m[1]!)}</code></pre>',
    );
    h = h.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m[1]}</code>');
    h = h.replaceAllMapped(
      RegExp(r'^### (.+)$', multiLine: true),
      (m) => '<h3>${m[1]}</h3>',
    );
    h = h.replaceAllMapped(
      RegExp(r'^## (.+)$', multiLine: true),
      (m) => '<h2>${m[1]}</h2>',
    );
    h = h.replaceAllMapped(
      RegExp(r'^# (.+)$', multiLine: true),
      (m) => '<h1>${m[1]}</h1>',
    );
    h = h.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (m) => '<strong>${m[1]}</strong>',
    );
    h = h.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => '<em>${m[1]}</em>');
    h = h.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) => '<a href="${m[2]}">${m[1]}</a>',
    );
    h = h.replaceAllMapped(
      RegExp(r'^- (.+)$', multiLine: true),
      (m) => '<li>${m[1]}</li>',
    );
    h = h.replaceAllMapped(
      RegExp(r'^> (.+)$', multiLine: true),
      (m) => '<blockquote>${m[1]}</blockquote>',
    );
    h = h.replaceAll(RegExp(r'^---$', multiLine: true), '<hr>');
    h = h.replaceAllMapped(RegExp(r'^\|(.+)\|$', multiLine: true), (m) {
      final cells = m[1]!
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty && !RegExp(r'^[-]+$').hasMatch(c));
      if (cells.isEmpty) return '';
      return '<tr>${cells.map((c) => '<td>$c</td>').join()}</tr>';
    });
    h = h.replaceAll('\n\n', '<br>');

    _iframe.srcdoc = '''<!DOCTYPE html><html><head><meta charset="UTF-8">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',system-ui,sans-serif;background:#0a0a14;color:#e4e4ef;padding:2.5rem;line-height:1.7;max-width:760px;margin:0 auto}
h1,h2,h3{color:#fff;margin:1.5rem 0 0.5rem}
h1{font-size:2rem;border-bottom:1px solid #252538;padding-bottom:0.4em}
code{background:#1a1a2e;padding:2px 8px;border-radius:6px;font-family:'Cascadia Code',monospace;color:#e06c75;font-size:0.9em}
pre{background:#1a1a2e;padding:1.2rem;border-radius:12px;overflow-x:auto;border:1px solid #252538;margin:1rem 0}
pre code{background:none;padding:0;color:#abb2bf}
blockquote{border-left:3px solid #7C3AED;padding-left:1rem;color:#8b8fa7;font-style:italic;margin:0.5rem 0}
table{border-collapse:collapse;width:100%;margin:1rem 0}
td{border:1px solid #252538;padding:10px 14px}
tr:nth-child(even){background:#12121e}
a{color:#a78bfa;text-decoration:none}
hr{border:none;border-top:1px solid #252538;margin:1.5rem 0}
ul{padding-left:1.5rem}li{margin:0.3rem 0}
strong{color:#fff}em{color:#a78bfa}
</style></head><body>$h</body></html>''';
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: Row(
              children: [
                // Left: Editor
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      _tabBar(),
                      Expanded(child: _editor()),
                      _statusBar(),
                    ],
                  ),
                ),
                // Gutter
                _gutter(),
                // Right: Preview
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      _previewBar(),
                      Expanded(child: _preview()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ──────────────────────────────────────────
  Widget _topBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      child: Row(
        children: [
          // Back
          _iconBtn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
          const SizedBox(width: 8),
          // Title pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accent.withValues(alpha: 0.15),
                  _accent.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_rounded, color: _accent, size: 14),
                const SizedBox(width: 6),
                const Text(
                  'Playground',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Reset
          _iconBtn(Icons.refresh_rounded, () {
            _htmlCtrl.text = _defaultHtml;
            _cssCtrl.text = _defaultCss;
            _jsCtrl.text = _defaultJs;
            _mdCtrl.text = _defaultMd;
            _run();
          }),
          const SizedBox(width: 6),
          // Run button
          _RunButton(onPressed: _run),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: _textMuted, size: 18),
        ),
      ),
    );
  }

  // ─── Tab Bar ──────────────────────────────────────────
  Widget _tabBar() {
    final tabs = [
      ('HTML', const Color(0xFFE34F26)),
      ('CSS', const Color(0xFF1572B6)),
      ('JS', const Color(0xFFF7DF1E)),
      ('MD', const Color(0xFF8B8FA7)),
    ];

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = _activeTab == i;
          return GestureDetector(
            onTap: () => _tabController.animateTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80,
              decoration: BoxDecoration(
                color: active ? _surfaceLight : Colors.transparent,
                border: Border(
                  top: BorderSide(
                    color: active ? _accent : Colors.transparent,
                    width: 2,
                  ),
                  right: BorderSide(color: _border.withValues(alpha: 0.5)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tabs[i].$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    tabs[i].$1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? Colors.white : _textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Editor ──────────────────────────────────────────
  Widget _editor() {
    return Container(
      color: _surfaceLight,
      child: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _textField(_htmlCtrl, 'html'),
          _textField(_cssCtrl, 'css'),
          _textField(_jsCtrl, 'javascript'),
          _textField(_mdCtrl, 'markdown'),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String lang) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Line numbers column
        Container(
          width: 42,
          padding: const EdgeInsets.only(top: 14, right: 12),
          color: _surface,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: ctrl,
            builder: (_, value, __) {
              final lineCount = '\n'.allMatches(value.text).length + 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  lineCount.clamp(1, 200),
                  (i) => Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: 'Cascadia Code, Consolas, monospace',
                      fontSize: 12,
                      height: 1.7,
                      color: _textDim,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Divider
        Container(width: 1, color: _border),
        // Code area
        Expanded(
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            cursorColor: _accent,
            style: const TextStyle(
              fontFamily: 'Cascadia Code, Consolas, monospace',
              fontSize: 13,
              height: 1.7,
              color: Color(0xFFCDD6F4),
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
              hintText: '// $lang',
              hintStyle: const TextStyle(color: _textDim),
            ),
            onChanged: (_) {
              if (_activeTab == 3) _runMd();
            },
          ),
        ),
      ],
    );
  }

  // ─── Status Bar ──────────────────────────────────────
  Widget _statusBar() {
    final langs = ['HTML', 'CSS', 'JavaScript', 'Markdown'];
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('Ready', style: TextStyle(fontSize: 11, color: _textMuted)),
          const Spacer(),
          Text(
            langs[_activeTab],
            style: TextStyle(fontSize: 11, color: _textMuted),
          ),
          const SizedBox(width: 12),
          Text('UTF-8', style: TextStyle(fontSize: 11, color: _textDim)),
        ],
      ),
    );
  }

  // ─── Gutter ──────────────────────────────────────────
  Widget _gutter() {
    return Container(
      width: 4,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accent.withValues(alpha: 0.3),
            _accent.withValues(alpha: 0.05),
          ],
        ),
      ),
    );
  }

  // ─── Preview Bar ─────────────────────────────────────
  Widget _previewBar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          // Traffic lights
          ...[
            const Color(0xFFFF5F57),
            const Color(0xFFFFBD2E),
            const Color(0xFF28C840),
          ].map(
            (c) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // URL bar
          Expanded(
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, size: 10, color: _green),
                  const SizedBox(width: 6),
                  Text(
                    'localhost:preview',
                    style: TextStyle(
                      fontSize: 11,
                      color: _textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Preview ─────────────────────────────────────────
  Widget _preview() {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return Container(
      color: _bg,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

// ─── Animated Run Button ─────────────────────────────
class _RunButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _RunButton({required this.onPressed});

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hover
                  ? [const Color(0xFF16A34A), const Color(0xFF22C55E)]
                  : [const Color(0xFF22C55E), const Color(0xFF16A34A)],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 15),
              const SizedBox(width: 4),
              const Text(
                'Run',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
