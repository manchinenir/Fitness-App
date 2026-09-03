import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const _navy    = Color(0xFF0A1628);
  static const _blue    = Color(0xFF1565C0);
  static const _sky     = Color(0xFF2196F3);
  static const _bg      = Color(0xFFF5F8FF);
  static const _card    = Color(0xFFFFFFFF);
  static const _text    = Color(0xFF0A1628);
  static const _sub     = Color(0xFF546E7A);
  static const _divider = Color(0xFFDDE6F7);

  final List<_ChatMsg> _messages = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _messages.add(const _ChatMsg(
      role: 'assistant',
      content: "Hi! I'm your Flex Facility AI fitness coach. Ask me anything about workouts, nutrition, recovery, or goal-setting — I'm here to help you crush your goals!",
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_ChatMsg(role: 'user', content: text));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'aiChat',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 85)),
      );
      final history = _messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      final result = await callable.call({'messages': history});
      final reply = ((result.data as Map)['reply'] as String?) ?? "Sorry, I couldn't get a response.";

      if (mounted) {
        setState(() {
          _messages.add(_ChatMsg(role: 'assistant', content: reply));
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(const _ChatMsg(
            role: 'assistant',
            content: "Sorry, I'm having trouble connecting right now. Please check your connection and try again.",
          ));
          _loading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(children: [
        Expanded(child: _buildMessageList()),
        if (_loading) _buildTypingRow(),
        _buildInputBar(),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_blue, _sky],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AI Fitness Coach',
              style: GoogleFonts.barlowCondensed(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          Text('Powered by Claude',
              style: GoogleFonts.barlow(fontSize: 11, color: Colors.white60)),
        ]),
      ]),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _buildBubble(_messages[i]),
    );
  }

  Widget _buildBubble(_ChatMsg msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: EdgeInsets.only(
        top: 3, bottom: 3,
        left: isUser ? 56 : 0,
        right: isUser ? 0 : 56,
      ),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_blue, _sky],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? _blue : _card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.07),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                msg.content,
                style: GoogleFonts.barlow(
                  fontSize: 14.5,
                  height: 1.45,
                  color: isUser ? Colors.white : _text,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTypingRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_blue, _sky]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(color: _navy.withValues(alpha: 0.07), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: const _TypingDots(),
        ),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _divider)),
        boxShadow: [
          BoxShadow(color: _navy.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: GoogleFonts.barlow(fontSize: 14.5, color: _text),
            decoration: InputDecoration(
              hintText: 'Ask your fitness coach...',
              hintStyle: GoogleFonts.barlow(fontSize: 14, color: _sub),
              filled: true,
              fillColor: _bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: _divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: _blue, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _loading ? null : _send,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: _loading
                  ? null
                  : const LinearGradient(
                      colors: [_navy, _blue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              color: _loading ? _divider : null,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.send_rounded,
              color: _loading ? _sub : Colors.white,
              size: 20,
            ),
          ),
        ),
      ]),
    );
  }
}

// Animated typing indicator dots
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
          final progress = (_ctrl.value + i * 0.25) % 1.0;
          final opacity = (progress < 0.5 ? progress * 2 : (1.0 - progress) * 2).clamp(0.25, 1.0);
          return Padding(
            padding: EdgeInsets.only(right: i < 2 ? 4.0 : 0.0),
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF1565C0),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }));
      },
    );
  }
}

class _ChatMsg {
  final String role;
  final String content;
  const _ChatMsg({required this.role, required this.content});
}
