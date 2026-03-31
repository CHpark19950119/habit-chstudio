import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// ═══════════════════════════════════════════════════════════
/// 소설 뷰어 v4 — 「허락」 제1부: 흙
/// assets/roadmap/허락_제1부_흙_v4.html 파싱 → Flutter 네이티브 렌더링
/// 11챕터 + 커버 + 챕터 탭 네비게이션
/// ═══════════════════════════════════════════════════════════

// ─── 파싱 블록 타입 ───
enum _BT {
  prose,
  sectionBreak,
  quoteBlock,
  quoteAttr,
  recordCard,
  dataCard,
  analysisPanel,
  circuitTitle,
  circuitFlow,
  photoSkip,
}

class _Block {
  final _BT type;
  final String text;
  final String? extra;
  final String? extra2;
  const _Block(this.type, this.text, {this.extra, this.extra2});
}

class _CoverData {
  final String title, sub, author, date, epigraph;
  const _CoverData({
    this.title = '',
    this.sub = '',
    this.author = '',
    this.date = '',
    this.epigraph = '',
  });
}

class _ChapterInfo {
  final String number, name, period;
  final List<_Block> blocks;
  const _ChapterInfo({
    required this.number,
    required this.name,
    required this.period,
    required this.blocks,
  });
  String get tabLabel => '$number $name';
}

class NovelViewerScreen extends StatefulWidget {
  const NovelViewerScreen({super.key});
  @override
  State<NovelViewerScreen> createState() => _NovelViewerScreenState();
}

class _NovelViewerScreenState extends State<NovelViewerScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _showCover = true;
  _CoverData _cover = const _CoverData();
  List<_ChapterInfo> _chapters = [];
  late TabController _tabCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  int _currentTab = 0;

  // v4 CSS 변수 매핑
  static const _bg = Color(0xFFF4EFE5);
  static const _tx = Color(0xFF18140F);
  static const _tx2 = Color(0xFF55504A);
  static const _tx3 = Color(0xFF8A847A);
  static const _ac = Color(0xFF8B2500);
  static const _ac2 = Color(0xFF2D5A7B);
  static const _bd = Color(0xFFC8BFAE);
  static const _sf = Color(0xFFE3DCCF);
  static const _bone = Color(0xFFE8DCC8);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _tabCtrl = TabController(length: 1, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // v4 단일 파일 로딩
      final html =
          await rootBundle.loadString('assets/roadmap/허락_제1부_흙_v4.html');

      final cover = _parseCover(html);
      final chapters = _parseChapters(html);

      if (!mounted) return;
      _tabCtrl.dispose();
      _tabCtrl = TabController(length: chapters.length, vsync: this);
      _tabCtrl.addListener(_onTabChanged);
      _safeSetState(() {
        _cover = cover;
        _chapters = chapters;
        _loading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      debugPrint('NovelViewer load error: $e');
      _safeSetState(() => _loading = false);
    }
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    _safeSetState(() => _currentTab = _tabCtrl.index);
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  // ═══════════════════════════════════════
  //  HTML 파서
  // ═══════════════════════════════════════

  _CoverData _parseCover(String html) {
    final coverRe = RegExp(
        r'<div class="cover"[^>]*>(.*?)</div>\s*<div class="reader"',
        dotAll: true);
    final cm = coverRe.firstMatch(html);
    final ch = cm?.group(1) ?? '';
    return _CoverData(
      title: _cls(ch, 'cover-title'),
      sub: _cls(ch, 'cover-sub'),
      author: _cls(ch, 'cover-author'),
      date: _cls(ch, 'cover-date'),
      epigraph: _divCls(ch, 'cover-epigraph'),
    );
  }

  List<_ChapterInfo> _parseChapters(String html) {
    final chapters = <_ChapterInfo>[];
    // 챕터 분리: data-chapter 속성 기준
    final starts = <int>[];
    final chStartRe = RegExp(r'<div class="chapter[^"]*"[^>]*data-chapter="\d+"');
    for (final m in chStartRe.allMatches(html)) {
      starts.add(m.start);
    }
    // 끝 지점: 다음 챕터 시작 또는 mode-toggle/script
    final endRe = RegExp(r'<div class="mode-toggle"');
    final endMatch = endRe.firstMatch(html);
    final docEnd = endMatch?.start ?? html.length;

    for (int i = 0; i < starts.length; i++) {
      final s = starts[i];
      final e = (i + 1 < starts.length) ? starts[i + 1] : docEnd;
      final chHtml = html.substring(s, e);

      final number = _cls(chHtml, 'ch-number');
      final name = _cls(chHtml, 'ch-name');
      final period = _cls(chHtml, 'ch-period');
      final blocks = _parseChapterBlocks(chHtml);

      chapters.add(_ChapterInfo(
        number: number,
        name: name,
        period: period,
        blocks: blocks,
      ));
    }
    return chapters;
  }

  List<_Block> _parseChapterBlocks(String chHtml) {
    final blocks = <_Block>[];

    // ch-header 닫는 지점 이후 ~ ch-nav-bottom 시작 이전을 본문으로 취급
    // ch-period가 헤더의 마지막 요소
    final periodRe = RegExp(r'<div class="ch-period">[^<]*</div>\s*</div>');
    final pm = periodRe.firstMatch(chHtml);
    if (pm == null) return blocks;
    final bodyStart = pm.end;

    // ch-nav-bottom이 본문 끝
    final navRe = RegExp(r'<div class="ch-nav-bottom">');
    final nm = navRe.firstMatch(chHtml);
    final bodyEnd = nm?.start ?? chHtml.length;

    if (bodyStart >= bodyEnd) return blocks;
    final body = chHtml.substring(bodyStart, bodyEnd);

    _parseBody(body, blocks);
    return blocks;
  }

  void _parseBody(String body, List<_Block> blocks) {
    // 토큰 매칭: 열린 태그 시작 위치를 찾아서 블록 종류 결정
    int pos = 0;
    while (pos < body.length) {
      // 다음 태그 찾기
      final nextTag = body.indexOf('<', pos);
      if (nextTag == -1) break;

      // 태그 전 텍스트는 무시 (공백 등)
      pos = nextTag;

      // 각 블록 타입 시도
      if (_startsWith(body, pos, '<div class="photo-illust"')) {
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          final inner = body.substring(pos, end);
          // base64 이미지 추출
          final imgRe = RegExp(r'src="data:image/[^;]+;base64,([^"]+)"');
          final imgMatch = imgRe.firstMatch(inner);
          final b64 = imgMatch?.group(1) ?? '';
          final caption = _cls(inner, 'photo-caption');
          blocks.add(_Block(_BT.photoSkip, b64, extra: caption));
          pos = end;
          continue;
        }
      }

      if (_startsWith(body, pos, '<div class="section-break"')) {
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          blocks.add(const _Block(_BT.sectionBreak, '*'));
          pos = end;
          continue;
        }
      }

      if (_startsWith(body, pos, '<div class="quote-block"')) {
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          final inner = body.substring(pos, end);
          _addQuoteBlock(inner, blocks);
          pos = end;
          continue;
        }
      }

      if (_startsWith(body, pos, '<div class="record-card"')) {
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          final inner = body.substring(pos, end);
          final grade = _cls(inner, 'grade');
          final comment = _cls(inner, 'comment');
          blocks.add(_Block(_BT.recordCard, grade, extra: comment));
          pos = end;
          continue;
        }
      }

      if (_startsWith(body, pos, '<div class="data-card"')) {
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          final inner = body.substring(pos, end);
          final label = _cls(inner, 'd-label');
          final value = _cls(inner, 'd-value');
          final note = _cls(inner, 'd-note');
          blocks.add(_Block(_BT.dataCard, label, extra: value, extra2: note));
          pos = end;
          continue;
        }
      }

      if (_startsWith(body, pos, '<div class="circuit"')) {
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          final inner = body.substring(pos, end);
          final title = _cls(inner, 'circuit-title');
          if (title.isNotEmpty) {
            blocks.add(_Block(_BT.circuitTitle, title));
          }
          final nodeRe = RegExp(
              r'<span class="circuit-(?:node|arrow)"[^>]*>(.*?)</span>',
              dotAll: true);
          final parts = <String>[];
          for (final nm in nodeRe.allMatches(inner)) {
            parts.add(_strip(nm.group(1) ?? '').trim());
          }
          if (parts.isNotEmpty) {
            blocks.add(_Block(_BT.circuitFlow, parts.join(' ')));
          }
          pos = end;
          continue;
        }
      }

      if (_startsWith(body, pos, '<div class="analysis-panel"')) {
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          final inner = body.substring(pos, end);
          final h4 = _tag(inner, 'h4');
          final bodyInner = _cls(inner, 'analysis-body-inner');
          if (h4.isNotEmpty || bodyInner.isNotEmpty) {
            blocks.add(_Block(_BT.analysisPanel, h4, extra: bodyInner));
          }
          pos = end;
          continue;
        }
      }

      if (_startsWith(body, pos, '<div class="prose"')) {
        // prose는 컨테이너 div — 내부를 재귀 파싱
        final end = _findBalancedDiv(body, pos);
        if (end > pos) {
          // 열린 태그 끝 찾기
          final closeAngle = body.indexOf('>', pos);
          if (closeAngle > pos && closeAngle < end) {
            final proseInner = body.substring(closeAngle + 1, end - 6);
            _parseBody(proseInner, blocks);
          }
          pos = end;
          continue;
        }
      }

      // <p> 태그
      if (_startsWith(body, pos, '<p>') || _startsWith(body, pos, '<p ')) {
        final closeP = body.indexOf('</p>', pos);
        if (closeP > pos) {
          final pEnd = closeP + 4;
          final inner =
              body.substring(body.indexOf('>', pos) + 1, closeP);
          final text = _strip(inner).trim();
          if (text.isNotEmpty) {
            blocks.add(_Block(_BT.prose, text));
          }
          pos = pEnd;
          continue;
        }
      }

      // 다른 태그 — 스킵
      pos++;
    }
  }

  // 균형 잡힌 div 닫기 찾기 (중첩 div 처리)
  int _findBalancedDiv(String html, int start) {
    // 열린 <div 태그의 닫는 > 찾기
    final firstClose = html.indexOf('>', start);
    if (firstClose == -1) return start;

    int depth = 1;
    int pos = firstClose + 1;
    while (pos < html.length && depth > 0) {
      final nextOpen = html.indexOf('<div', pos);
      final nextClose = html.indexOf('</div>', pos);

      if (nextClose == -1) break;

      if (nextOpen != -1 && nextOpen < nextClose) {
        depth++;
        pos = nextOpen + 4;
      } else {
        depth--;
        if (depth == 0) {
          return nextClose + 6; // length of '</div>'
        }
        pos = nextClose + 6;
      }
    }
    return start; // 실패
  }

  bool _startsWith(String s, int pos, String prefix) {
    if (pos + prefix.length > s.length) return false;
    return s.substring(pos, pos + prefix.length) == prefix;
  }

  void _addQuoteBlock(String html, List<_Block> blocks) {
    final attrRe =
        RegExp(r'<div class="q-attr">(.*?)</div>', dotAll: true);
    final attrMatch = attrRe.firstMatch(html);
    String bodyPart = html;
    if (attrMatch != null) {
      bodyPart = html.substring(0, attrMatch.start);
    }
    final text = _strip(bodyPart).trim();
    if (text.isNotEmpty) blocks.add(_Block(_BT.quoteBlock, text));
    if (attrMatch != null) {
      final attr = _strip(attrMatch.group(1) ?? '').trim();
      if (attr.isNotEmpty) blocks.add(_Block(_BT.quoteAttr, attr));
    }
  }

  // ─── 유틸 ───
  String _cls(String html, String className) {
    final re = RegExp(
      '<[^>]+class="[^"]*\\b$className\\b[^"]*"[^>]*>(.*?)</[a-z]+>',
      dotAll: true,
    );
    final m = re.firstMatch(html);
    if (m == null) return '';
    return _strip(m.group(1) ?? '').trim();
  }

  String _divCls(String html, String className) {
    final re = RegExp(
      '<div[^>]+class="[^"]*\\b$className\\b[^"]*"[^>]*>(.*?)</div>',
      dotAll: true,
    );
    final m = re.firstMatch(html);
    if (m == null) return '';
    String content = m.group(1) ?? '';
    content = content.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    return _strip(content).trim();
  }

  String _tag(String html, String tag) {
    final re = RegExp('<$tag[^>]*>(.*?)</$tag>', dotAll: true);
    final m = re.firstMatch(html);
    if (m == null) return '';
    return _strip((m.group(1) ?? '').replaceAll(RegExp(r'<br\s*/?>'), '\n'))
        .trim();
  }

  String _strip(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&ndash;', '\u2013');
  }

  // ═══════════════════════════════════════
  //  위젯 빌더
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _showCover ? const Color(0xFF0F0D0A) : _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _ac))
          : _chapters.isEmpty
              ? _buildError()
              : _showCover
                  ? _buildCover()
                  : FadeTransition(
                      opacity: _fadeAnim, child: _buildReader()),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.menu_book_rounded, size: 48, color: _tx3),
        const SizedBox(height: 16),
        const Text('소설을 불러올 수 없습니다',
            style: TextStyle(
                fontFamily: 'NotoSerifKR', fontSize: 16, color: _tx2)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('돌아가기', style: TextStyle(color: _ac)),
        ),
      ]),
    );
  }

  // ═══ 커버 ═══
  Widget _buildCover() {
    return GestureDetector(
      onTap: _enterReader,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0908),
              Color(0xFF1A1510),
              Color(0xFF2A2118),
              Color(0xFF3A2E1E),
            ],
            stops: [0.0, 0.4, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              Text(
                _cover.title.isNotEmpty ? _cover.title : '허락',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'NotoSerifKR',
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: _bone,
                  letterSpacing: 12,
                  height: 1.2,
                  shadows: [
                    Shadow(color: Color(0x408B2500), blurRadius: 60),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _cover.sub.isNotEmpty ? _cover.sub : '제1부 \u2014 흙',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'NotoSerifKR',
                  fontSize: 15,
                  fontWeight: FontWeight.w200,
                  color: Color(0xFF9A8E7C),
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 48),
              if (_cover.author.isNotEmpty)
                Text(
                  _cover.author,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF6B5F4F),
                    letterSpacing: 4,
                  ),
                ),
              if (_cover.date.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _cover.date,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF4A4438),
                    letterSpacing: 2,
                  ),
                ),
              ],
              if (_cover.epigraph.isNotEmpty) ...[
                const SizedBox(height: 48),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                  decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(
                            color: _ac.withValues(alpha: 0.35), width: 2)),
                  ),
                  child: Text(
                    _cover.epigraph,
                    style: const TextStyle(
                      fontFamily: 'NotoSerifKR',
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF8A7E6C),
                      height: 2.0,
                    ),
                  ),
                ),
              ],
              const Spacer(flex: 2),
              Text(
                '터치하여 시작',
                style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFF5A5040).withValues(alpha: 0.7),
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _enterReader() {
    setState(() => _showCover = false);
    _fadeCtrl.reset();
    _fadeCtrl.forward();
  }

  // ═══ 리더 ═══
  Widget _buildReader() {
    return Column(
      children: [
        _buildAppBar(),
        _buildChapterTabs(),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children:
                _chapters.map((ch) => _buildChapterContent(ch)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 4,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: _bg.withValues(alpha: 0.95),
        border:
            const Border(bottom: BorderSide(color: _bd, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: _tx2),
            onPressed: () {
              if (!_showCover) {
                setState(() => _showCover = true);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          const Text(
            '허락',
            style: TextStyle(
              fontFamily: 'NotoSerifKR',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ac,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '제1부 흙',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w300, color: _tx3),
          ),
          const Spacer(),
          Text(
            '${_currentTab + 1} / ${_chapters.length}',
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, color: _tx3),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterTabs() {
    return Container(
      height: 42,
      color: _bg,
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: _ac,
        indicatorWeight: 2,
        labelColor: _ac,
        unselectedLabelColor: _tx3,
        labelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        dividerColor: _bd.withValues(alpha: 0.3),
        tabs: _chapters.map((ch) => Tab(text: ch.tabLabel)).toList(),
      ),
    );
  }

  Widget _buildChapterContent(_ChapterInfo ch) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildChapterHeader(ch)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _buildBlock(ch.blocks[i]),
              childCount: ch.blocks.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildChapterNav(ch)),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  // ═══ 챕터 헤더 ═══
  Widget _buildChapterHeader(_ChapterInfo ch) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _bd, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ch.number.isNotEmpty)
            Text(
              ch.number,
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w300,
                color: _sf,
                height: 1.0,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (ch.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ch.name,
                style: const TextStyle(
                  fontFamily: 'NotoSerifKR',
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: _tx,
                  letterSpacing: -1.5,
                  height: 1.2,
                ),
              ),
            ),
          if (ch.period.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                ch.period,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _tx3,
                  letterSpacing: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══ 블록 렌더링 ═══
  Widget _buildBlock(_Block b) {
    switch (b.type) {
      case _BT.prose:
        return _proseW(b.text);
      case _BT.sectionBreak:
        return _sectionBreakW();
      case _BT.quoteBlock:
        return _quoteW(b.text);
      case _BT.quoteAttr:
        return _quoteAttrW(b.text);
      case _BT.recordCard:
        return _recordCardW(b.text, b.extra ?? '');
      case _BT.dataCard:
        return _dataCardW(b.text, b.extra ?? '', b.extra2 ?? '');
      case _BT.analysisPanel:
        return _AnalysisW(title: b.text, body: b.extra ?? '');
      case _BT.circuitTitle:
        return _circuitTitleW(b.text);
      case _BT.circuitFlow:
        return _circuitFlowW(b.text);
      case _BT.photoSkip:
        return _photoSkipW(b.text, b.extra ?? '');
    }
  }

  // ─── 산문 ───
  Widget _proseW(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text(text,
          style: const TextStyle(
            fontFamily: 'NotoSerifKR',
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: _tx,
            height: 2.05,
            letterSpacing: -0.15,
          )),
    );
  }

  // ─── 구분선 ───
  Widget _sectionBreakW() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: SizedBox(
          width: 60,
          height: 24,
          child: CustomPaint(painter: _WavePainter()),
        ),
      ),
    );
  }

  // ─── 인용문 ───
  Widget _quoteW(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 4),
      padding: const EdgeInsets.fromLTRB(24, 22, 20, 22),
      decoration: BoxDecoration(
        border: const Border(left: BorderSide(color: _ac, width: 3)),
        gradient: LinearGradient(
          colors: [_ac.withValues(alpha: 0.04), Colors.transparent],
        ),
      ),
      child: Text(text,
          style: const TextStyle(
            fontFamily: 'NotoSerifKR',
            fontSize: 14.5,
            fontWeight: FontWeight.w400,
            color: _tx,
            height: 2.0,
            fontStyle: FontStyle.italic,
          )),
    );
  }

  Widget _quoteAttrW(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, bottom: 24),
      child: Text(text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: _tx3,
            letterSpacing: 1.5,
          )),
    );
  }

  // ─── 생활기록부 카드 ───
  Widget _recordCardW(String grade, String comment) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEBE5D8),
        border: Border.all(color: _bd, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(18, -9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: _bg,
              child: const Text('생활기록부',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: _tx3,
                    letterSpacing: 1.5,
                  )),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (grade.isNotEmpty)
                  Text(grade,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _ac,
                        letterSpacing: 0.5,
                      )),
                if (grade.isNotEmpty && comment.isNotEmpty)
                  const SizedBox(height: 6),
                if (comment.isNotEmpty)
                  Text(comment,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _tx2,
                        height: 1.9,
                      )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ─── 데이터 카드 ───
  Widget _dataCardW(String label, String value, String note) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEBE5D8),
        border: Border.all(color: _bd, width: 0.5),
      ),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: _ac2, width: 3)),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Text(label,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _ac2,
                    letterSpacing: 2,
                  )),
            if (value.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _tx,
                  )),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(note,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: _tx3,
                    height: 1.8,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ─── 회로 시각화 ───
  Widget _circuitTitleW(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B17), Color(0xFF141210)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: Color(0xFF8B6520),
            letterSpacing: 3,
          )),
    );
  }

  Widget _circuitFlowW(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B17), Color(0xFF141210)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 8,
        children: text.split(' ').map((part) {
          final t = part.trim();
          if (t.isEmpty) return const SizedBox.shrink();
          if (t == '\u2192' || t == '→') {
            return const Text('→',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ac));
          }
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF5A4A30)),
              color: _ac.withValues(alpha: 0.12),
            ),
            child: Text(t,
                style: const TextStyle(
                    fontSize: 12, color: _bone, height: 1.2)),
          );
        }).toList(),
      ),
    );
  }

  // ─── 삽화 ───
  Widget _photoSkipW(String b64, String caption) {
    if (b64.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: _sf.withValues(alpha: 0.5),
          border: Border.all(color: _bd, width: 0.5),
        ),
        child: const Center(
          child: Column(children: [
            Icon(Icons.image_outlined, size: 28, color: _tx3),
            SizedBox(height: 6),
            Text('삽화',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: _tx3,
                    letterSpacing: 2)),
          ]),
        ),
      );
    }

    Uint8List? bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      bytes = null;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.memory(bytes, width: double.infinity, fit: BoxFit.fitWidth),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            color: _sf.withValues(alpha: 0.5),
            child: const Center(child: Icon(Icons.broken_image_outlined, size: 28, color: _tx3)),
          ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: _tx3,
                  letterSpacing: 1.5,
                  height: 1.6,
                )),
          ),
      ]),
    );
  }

  // ─── 챕터 네비 ───
  Widget _buildChapterNav(_ChapterInfo ch) {
    final idx = _chapters.indexOf(ch);
    final hasPrev = idx > 0;
    final hasNext = idx < _chapters.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
      child: Column(children: [
        const Divider(color: _bd, height: 1),
        const SizedBox(height: 32),
        Row(children: [
          if (hasPrev)
            Expanded(
              child: _navBtn(
                '\u2190 이전',
                _chapters[idx - 1].tabLabel,
                () => _tabCtrl.animateTo(idx - 1),
              ),
            )
          else
            const Expanded(child: SizedBox()),
          const SizedBox(width: 16),
          if (hasNext)
            Expanded(
              child: _navBtn(
                '다음 \u2192',
                _chapters[idx + 1].tabLabel,
                () => _tabCtrl.animateTo(idx + 1),
                alignEnd: true,
              ),
            )
          else
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: _bd, width: 0.5),
                  color: _sf.withValues(alpha: 0.5),
                ),
                child: const Text('제1부 끝',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _tx3,
                      letterSpacing: 1,
                    )),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _navBtn(String dir, String label, VoidCallback onTap,
      {bool alignEnd = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: _bd, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(dir,
                style: const TextStyle(
                    fontSize: 10, color: _tx3, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _tx)),
          ],
        ),
      ),
    );
  }
}

// ═══ 분석 패널 (접기/펼치기) — StatefulWidget ═══
class _AnalysisW extends StatefulWidget {
  final String title, body;
  const _AnalysisW({required this.title, required this.body});
  @override
  State<_AnalysisW> createState() => _AnalysisWState();
}

class _AnalysisWState extends State<_AnalysisW> {
  bool _open = false;

  static const _ac2 = Color(0xFF2D5A7B);
  static const _tx2 = Color(0xFF55504A);
  static const _tx3 = Color(0xFF8A847A);
  static const _bd = Color(0xFFC8BFAE);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEBE5D8),
        border: Border.all(color: _bd, width: 0.5),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: _ac2, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _ac2,
                      letterSpacing: -0.3,
                    )),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: const Text('\u25BC',
                    style: TextStyle(fontSize: 12, color: _tx3)),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Text(widget.body,
                style: const TextStyle(
                    fontSize: 13, color: _tx2, height: 1.95)),
          ),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ]),
    );
  }
}

// ═══ 물결 구분선 페인터 ═══
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC8BFAE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final path = Path();
    final w = size.width;
    final h = size.height;
    final mid = h / 2;

    path.moveTo(0, mid);
    final seg = w / 6;
    for (int i = 0; i < 3; i++) {
      final x0 = seg * (i * 2);
      path.cubicTo(
          x0 + seg * 0.3, mid - 4, x0 + seg * 0.7, mid - 4, x0 + seg, mid);
      path.cubicTo(x0 + seg * 1.3, mid + 4, x0 + seg * 1.7, mid + 4,
          x0 + seg * 2, mid);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
