import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/providers/coins_provider.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/data/chat_suggestions.dart';
import 'package:medicoscope/models/chat_message.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/services/appointment_service.dart';
import 'package:medicoscope/services/chat_service.dart';
import 'package:medicoscope/services/disease_result_pipeline.dart';
import 'package:medicoscope/services/disease_risk_store.dart';

/// The shared medical-assistant chat body: message list + streaming + markdown +
/// context chips + suggested prompts + input. Hosted by both the full-screen
/// [ChatScreen] and the draggable bottom sheet, so there is one implementation.
class ChatView extends StatefulWidget {
  final bool fullScreen;
  final String? presetPrompt;
  const ChatView({super.key, this.fullScreen = false, this.presetPrompt});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];

  bool _isLoading = false;
  bool _profileLoaded = false;
  bool _hasHealthData = false;
  String _medicalProfile = '';
  String _streamingText = '';
  String _lastUserText = '';
  bool _showScrollDown = false;
  final List<String> _contextChips = [];

  int _seq = 0;
  String _nextId() => 'm${_seq++}';

  Color get _accent => AppTheme.chatTeal;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMedicalSummary().then((_) {
      final preset = widget.presetPrompt?.trim();
      if (preset != null && preset.isNotEmpty) _send(preset);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.offset >= _scroll.position.maxScrollExtent - 120;
    if (atBottom == _showScrollDown) {
      setState(() => _showScrollDown = !atBottom);
    }
  }

  // ── Medical context ───────────────────────────────────────────────────────
  Future<void> _loadMedicalSummary() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token == null || auth.user == null) {
      _profileLoaded = true;
      _addGreeting();
      return;
    }

    final parts = <String>[
      'Name: ${auth.user!.name}',
      'Role: ${auth.user!.role}',
    ];
    if (auth.user!.phone != null && auth.user!.phone!.isNotEmpty) {
      parts.add('Phone: ${auth.user!.phone}');
    }

    try {
      final api = ApiService(token: auth.token);
      final data = await api
          .get(ApiConstants.patientMedicalSummary)
          .timeout(const Duration(seconds: 10));

      final patient = data['patient'] as Map<String, dynamic>? ?? {};
      final conditions = List<String>.from(patient['conditions'] ?? []);
      final medications = List<String>.from(patient['medications'] ?? []);
      final bloodGroup = patient['bloodGroup'] ?? '';
      final dob = patient['dateOfBirth'];

      if (bloodGroup.toString().isNotEmpty) {
        parts.add('Blood Group: $bloodGroup');
        _contextChips.add('Blood $bloodGroup');
      }
      if (dob != null) parts.add('Date of Birth: $dob');
      if (conditions.isNotEmpty) {
        parts.add('Medical Conditions: ${conditions.join(', ')}');
        for (final c in conditions.take(3)) {
          _contextChips.add(c.toString());
        }
      }
      if (medications.isNotEmpty) {
        parts.add('Current Medications: ${medications.join(', ')}');
      }

      final detections =
          List<Map<String, dynamic>>.from(data['detections'] ?? []);
      if (detections.isNotEmpty) {
        _hasHealthData = true;
        parts.add('\n--- Recent Detection Results ---');
        for (final d in detections) {
          final cat = d['category'] ?? '';
          final cls = d['className'] ?? '';
          final conf = d['confidence'];
          final date = d['date'] ?? '';
          final desc = d['description'] ?? '';
          final confStr = cat == 'heart_sound'
              ? '${conf?.toStringAsFixed(0)} BPM'
              : '${((conf ?? 0) * 100).toStringAsFixed(1)}% confidence';
          parts.add('- [$cat] $cls ($confStr) on ${_formatDate(date)}');
          if (desc.toString().isNotEmpty) parts.add('  Description: $desc');
        }
        _contextChips.add('${detections.length} recent scan(s)');
      }

      final vitals = List<Map<String, dynamic>>.from(data['vitals'] ?? []);
      if (vitals.isNotEmpty) {
        _hasHealthData = true;
        parts.add('\n--- Recent Vitals Sessions ---');
        for (final v in vitals) {
          final date = v['date'] ?? '';
          parts.add(
            '- HR: avg ${v['avgHeartRate']?.toStringAsFixed(0)}'
            ' (${v['minHeartRate']?.toStringAsFixed(0)}-${v['maxHeartRate']?.toStringAsFixed(0)})'
            ', BP: ${v['avgSystolic']?.toStringAsFixed(0)}/${v['avgDiastolic']?.toStringAsFixed(0)}'
            ', SpO2: ${v['avgSpO2']?.toStringAsFixed(1)}%'
            ' on ${_formatDate(date)}',
          );
          final alerts = List<Map<String, dynamic>>.from(v['alerts'] ?? []);
          for (final a in alerts) {
            parts.add('  ALERT: ${a['message']}');
          }
        }
        final v0 = vitals.first;
        _contextChips.add(
            'BP ${v0['avgSystolic']?.toStringAsFixed(0)}/${v0['avgDiastolic']?.toStringAsFixed(0)}');
      }
    } catch (e) {
      debugPrint('Medical summary fetch failed: $e');
    }

    try {
      final diseaseSummary = await DiseaseRiskStore.chatbotSummary();
      if (diseaseSummary.isNotEmpty) {
        _hasHealthData = true;
        parts.add('\n--- Disease Screening Results ---');
        parts.add(diseaseSummary);
      }
    } catch (_) {}

    _medicalProfile = parts.join('\n');
    _profileLoaded = true;
    _addGreeting();
  }

  void _addGreeting() {
    if (!mounted) return;
    final lang =
        Provider.of<LocaleProvider>(context, listen: false).languageCode;
    final greeting = _hasHealthData
        ? AppStrings.get('chatbot_greeting_context', lang)
        : AppStrings.get('chatbot_greeting', lang);
    setState(() => _messages.add(
        ChatMessage(id: _nextId(), text: greeting, isUser: false)));
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return date.toString();
    }
  }

  // ── Send / stream ─────────────────────────────────────────────────────────
  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _isLoading) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final sessionId = auth.user?.id ?? 'anonymous';

    if (!_profileLoaded) await _loadMedicalSummary();

    try {
      final fresh = await DiseaseRiskStore.chatbotSummary();
      if (fresh.isNotEmpty && !_medicalProfile.contains(fresh)) {
        _medicalProfile =
            '$_medicalProfile\n--- Disease Screening Results (live) ---\n$fresh';
        _hasHealthData = true;
      }
    } catch (_) {}

    setState(() {
      _messages.add(ChatMessage(id: _nextId(), text: text, isUser: true));
      _lastUserText = text;
      _streamingText = '';
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    if (_matchesAppointmentIntent(text)) {
      await _handleAppointmentIntent(text, auth);
      return;
    }

    final lang =
        Provider.of<LocaleProvider>(context, listen: false).languageCode;

    try {
      final stream = ChatService.sendMessageStream(
        message: text,
        sessionId: sessionId,
        patientProfile: _medicalProfile,
        language: lang,
        medicalContext: _medicalProfile,
      );
      await for (final token in stream) {
        if (!mounted) return;
        setState(() => _streamingText += token);
        _scrollToBottom();
      }
      final finalText = _streamingText;
      if (mounted) {
        setState(() {
          if (finalText.isNotEmpty) {
            _messages.add(
                ChatMessage(id: _nextId(), text: finalText, isUser: false));
          }
          _streamingText = '';
          _isLoading = false;
        });
      }
      if (auth.token != null && finalText.isNotEmpty) {
        unawaited(ChatService.saveMessageToDb(
          token: auth.token!,
          sessionId: sessionId,
          userMessage: text,
          assistantMessage: finalText,
        ));
      }
      if (mounted) {
        await Provider.of<CoinsProvider>(context, listen: false).addChatCoins();
      }
      _scrollToBottom();
      return;
    } catch (e) {
      debugPrint('Chat stream failed: $e');
    }

    // Non-streaming fallback.
    try {
      final reply = await ChatService.sendMessage(
        message: text,
        sessionId: sessionId,
        patientProfile: _medicalProfile,
        language: lang,
        medicalContext: _medicalProfile,
      );
      if (mounted) {
        setState(() {
          _streamingText = '';
          _messages
              .add(ChatMessage(id: _nextId(), text: reply, isUser: false));
          _isLoading = false;
        });
      }
      if (auth.token != null && reply.isNotEmpty) {
        unawaited(ChatService.saveMessageToDb(
          token: auth.token!,
          sessionId: sessionId,
          userMessage: text,
          assistantMessage: reply,
        ));
      }
      if (mounted) {
        await Provider.of<CoinsProvider>(context, listen: false).addChatCoins();
      }
    } catch (e) {
      final err = e.toString();
      String msg;
      if (err.contains('quota') ||
          err.contains('rate_limit') ||
          err.contains('Rate limit')) {
        msg =
            'The AI service has hit its daily free-tier quota. It resets shortly, please try again in a few minutes.';
      } else if (err.contains('warming up') || err.contains('503')) {
        msg = AppStrings.get('chatbot_warming_up', lang);
      } else if (err.contains('TimeoutException') || err.contains('timed out')) {
        msg = AppStrings.get('request_timed_out', lang);
      } else {
        msg = AppStrings.get('chatbot_error', lang);
      }
      if (mounted) {
        setState(() {
          _streamingText = '';
          _messages.add(ChatMessage(id: _nextId(), text: msg, isUser: false));
          _isLoading = false;
        });
      }
    }
    _scrollToBottom();
  }

  void _regenerate() {
    if (_isLoading || _lastUserText.isEmpty) return;
    // Drop the last assistant reply, then re-ask.
    setState(() {
      if (_messages.isNotEmpty && !_messages.last.isUser) {
        _messages.removeLast();
      }
    });
    _send(_lastUserText);
  }

  // ── Appointment intent (ported) ──────────────────────────────────────────
  bool _matchesAppointmentIntent(String raw) {
    final t = raw.toLowerCase();
    const bookVerbs = ['book', 'schedule', 'fix', 'set up', 'arrange', 'make'];
    const nouns = [
      'appointment', 'appt', 'visit', 'consult', 'consultation',
      'meeting with doctor', 'see my doctor', 'see a doctor', 'see the doctor',
      'doctor visit',
    ];
    for (final v in bookVerbs) {
      for (final n in nouns) {
        if (t.contains(v) && t.contains(n)) return true;
      }
    }
    if (t.contains('appointment') &&
        (t.contains('with') ||
            t.contains('please') ||
            t.contains('want') ||
            t.contains('can you'))) {
      return true;
    }
    return false;
  }

  Future<void> _handleAppointmentIntent(String text, AuthProvider auth) async {
    void reply(String s) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(id: _nextId(), text: s, isUser: false));
        _isLoading = false;
      });
      _scrollToBottom();
    }

    final user = auth.user;
    if (user == null) {
      return reply('Please sign in first so I can book the appointment for you.');
    }
    final doctorId = await DiseaseResultPipeline.resolveDoctorIdFor(auth.token);
    if (doctorId == null || doctorId.isEmpty) {
      return reply(
          'I could not find a doctor linked to your account yet. Open the MedicoScope drawer, tap Link Doctor, then try again.');
    }
    final slot = AppointmentService.parseSlot(text);
    try {
      await AppointmentService.book(
        doctorId: doctorId,
        patientId: user.id,
        patientName: user.name,
        preferredSlot: slot,
        modality: 'general',
        reason: 'Requested via MedicoScope chat: "$text"',
        authToken: auth.token,
      );
      reply(
          'Done. I have sent an appointment request to your linked doctor for ${_fmtSlot(slot)}. You will see a confirmation once they respond.');
    } catch (_) {
      reply(
          'Sorry, I could not reach the booking service just now. Please try again in a moment.');
    }
  }

  String _fmtSlot(DateTime d) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    final mi = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month]}, $h:$mi $ap';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final showSuggestions = _messages.length <= 1 && !_isLoading;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              (!_profileLoaded && _messages.isEmpty)
                  ? _loadingState(isDark)
                  : ListView(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      children: [
                        if (_contextChips.isNotEmpty) _contextHeader(isDark),
                        for (int i = 0; i < _messages.length; i++)
                          _bubble(_messages[i],
                              isLast: i == _messages.length - 1, isDark: isDark),
                        if (_isLoading && _streamingText.isNotEmpty)
                          _bubble(
                              ChatMessage(
                                  id: 'stream',
                                  text: _streamingText,
                                  isUser: false,
                                  streaming: true),
                              isLast: true,
                              isDark: isDark),
                        if (_isLoading && _streamingText.isEmpty)
                          _typing(isDark),
                        if (showSuggestions) _suggestionCards(isDark),
                        const SizedBox(height: 4),
                      ],
                    ),
              if (_showScrollDown)
                Positioned(
                  right: 12,
                  bottom: 8,
                  child: FloatingActionButton.small(
                    heroTag: 'chatScrollDown${widget.fullScreen}',
                    backgroundColor: _accent,
                    onPressed: _scrollToBottom,
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        // Quick-suggestion chip row (always available, compact).
        if (!showSuggestions) _quickRow(isDark),
        _inputBar(isDark, lang, bottomPad),
      ],
    );
  }

  Widget _loadingState(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(_accent)),
            ),
            const SizedBox(height: 10),
            Text('Loading your health data...',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        isDark ? AppTheme.darkTextGray : AppTheme.textGray)),
          ],
        ),
      );

  Widget _contextHeader(bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in _contextChips)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _accent.withValues(alpha: .3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, size: 12, color: _accent),
                  const SizedBox(width: 5),
                  Text(c,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.chatTealDark)),
                ]),
              ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms);

  Widget _bubble(ChatMessage m, {required bool isLast, required bool isDark}) {
    final child = m.isUser
        ? _userBubble(m, isDark)
        : _assistantBubble(m, isLast: isLast, isDark: isDark);
    return child
        .animate()
        .fadeIn(duration: 240.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOut);
  }

  Widget _userBubble(ChatMessage m, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 48),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onLongPress: () => _copy(m.text),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                gradient: AppTheme.chatGradient,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(m.text,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13.5, height: 1.4)),
            ),
          ),
        ),
      );

  Widget _assistantBubble(ChatMessage m,
      {required bool isLast, required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _copy(m.text),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    borderRadius: 14,
                    child: MarkdownBody(
                      data: m.text + (m.streaming ? ' ▌' : ''),
                      styleSheet: _mdStyle(isDark),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Actions on the finished last assistant message.
          if (isLast && !m.streaming && !_isLoading)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Row(children: [
                _miniAction(Icons.copy_rounded, 'Copy', () => _copy(m.text)),
                const SizedBox(width: 14),
                _miniAction(
                    Icons.refresh_rounded, 'Regenerate', _regenerate),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _miniAction(IconData icon, String label, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: _accent),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _accent)),
          ]),
        ),
      );

  Widget _avatar() => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          gradient: AppTheme.chatGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.smart_toy_outlined,
            color: Colors.white, size: 15),
      );

  MarkdownStyleSheet _mdStyle(bool isDark) {
    final base = isDark ? AppTheme.darkTextLight : AppTheme.textDark;
    return MarkdownStyleSheet(
      p: TextStyle(fontSize: 13.5, height: 1.45, color: base),
      strong: TextStyle(fontWeight: FontWeight.w800, color: base),
      listBullet: TextStyle(fontSize: 13.5, height: 1.45, color: base),
      h1: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: base),
      h2: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: base),
      h3: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: base),
      code: TextStyle(
          fontSize: 12.5,
          backgroundColor:
              (isDark ? Colors.white : Colors.black).withValues(alpha: .06),
          color: AppTheme.chatTealDark),
      blockquoteDecoration: BoxDecoration(
        color: _accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _typing(bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 10, right: 40),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _avatar(),
          const SizedBox(width: 8),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderRadius: 14,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _dot(0),
              const SizedBox(width: 5),
              _dot(1),
              const SizedBox(width: 5),
              _dot(2),
            ]),
          ),
        ]),
      );

  Widget _dot(int i) => Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            gradient: AppTheme.chatGradient, shape: BoxShape.circle),
      )
          .animate(onPlay: (c) => c.repeat())
          .scaleXY(
              begin: 0.6,
              end: 1.0,
              duration: 500.ms,
              delay: (i * 160).ms,
              curve: Curves.easeInOut)
          .then()
          .scaleXY(begin: 1.0, end: 0.6, duration: 500.ms);

  Widget _suggestionCards(bool isDark) {
    final items = buildChatSuggestions(hasHealthData: _hasHealthData);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Try asking',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkTextGray : AppTheme.textGray)),
          const SizedBox(height: 8),
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _send(items[i].prompt),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  borderRadius: 14,
                  child: Row(children: [
                    Icon(items[i].icon, size: 18, color: _accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(items[i].label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark)),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 12,
                        color:
                            isDark ? AppTheme.darkTextDim : AppTheme.textLight),
                  ]),
                ),
              ),
            )
                .animate()
                .fadeIn(delay: (i * 80).ms, duration: 260.ms)
                .slideX(begin: 0.06, end: 0),
        ],
      ),
    );
  }

  Widget _quickRow(bool isDark) {
    final items = buildChatSuggestions(hasHealthData: _hasHealthData);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ActionChip(
          avatar: Icon(items[i].icon, size: 15, color: _accent),
          label: Text(items[i].label, style: const TextStyle(fontSize: 11.5)),
          onPressed: _isLoading ? null : () => _send(items[i].prompt),
          backgroundColor: _accent.withValues(alpha: .10),
          side: BorderSide(color: _accent.withValues(alpha: .25)),
          labelStyle: TextStyle(
              color: isDark ? AppTheme.darkTextLight : AppTheme.textDark),
        ),
      ),
    );
  }

  Widget _inputBar(bool isDark, String lang, double bottomPad) => Container(
        padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomPad),
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.darkCard.withValues(alpha: .7)
              : Colors.white.withValues(alpha: .85),
          border: Border(
              top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade300)),
        ),
        child: Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: .06),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _send(_controller.text),
                style: TextStyle(
                    fontSize: 14,
                    color:
                        isDark ? AppTheme.darkTextLight : AppTheme.textDark),
                decoration: InputDecoration(
                  hintText: AppStrings.get('ask_about_health', lang),
                  hintStyle: TextStyle(
                      color:
                          isDark ? AppTheme.darkTextDim : AppTheme.textLight,
                      fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isLoading ? null : () => _send(_controller.text),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: AppTheme.chatGradient,
                borderRadius: BorderRadius.circular(21),
                boxShadow: [
                  BoxShadow(
                      color: _accent.withValues(alpha: .35),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(Icons.send_rounded,
                  color: _isLoading ? Colors.white54 : Colors.white, size: 19),
            ),
          ),
        ]),
      );

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
  }
}
