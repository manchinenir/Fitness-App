import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// ─── Trainer inbox: list of all client conversations ────────────────────────

class AdminMessagesScreen extends StatelessWidget {
  const AdminMessagesScreen({super.key});

  static const _navy = Color(0xFF1C2D5E);
  static const _blue = Color(0xFF2563EB);
  static const _bg   = Color(0xFFF5F7FB);
  static const _card = Color(0xFFFFFFFF);
  static const _text = Color(0xFF111827);
  static const _sub  = Color(0xFF6B7280);
  static const _div  = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Client Messages',
            style: GoogleFonts.barlowCondensed(
                fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('messages')
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mark_chat_unread_rounded, size: 60, color: _div),
                const SizedBox(height: 12),
                Text('No messages yet',
                    style: GoogleFonts.barlowCondensed(
                        fontSize: 20, fontWeight: FontWeight.w700, color: _sub)),
                const SizedBox(height: 4),
                Text('Client messages will appear here',
                    style: GoogleFonts.barlow(fontSize: 13, color: _sub)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: _div, indent: 72),
            itemBuilder: (_, i) => _ConvTile(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _ConvTile extends StatelessWidget {
  final DocumentSnapshot doc;
  const _ConvTile({required this.doc});

  static const _navy = Color(0xFF1C2D5E);
  static const _blue = Color(0xFF2563EB);
  static const _text = Color(0xFF111827);
  static const _sub  = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final clientName  = d['clientName'] as String? ?? 'Client';
    final lastMsg     = d['lastMessage'] as String? ?? '';
    final unread      = (d['unreadByTrainer'] as int?) ?? 0;
    final ts          = d['lastMessageTime'] as Timestamp?;
    final timeLabel   = ts != null ? _formatTime(ts.toDate()) : '';
    final initials    = clientName.isNotEmpty ? clientName[0].toUpperCase() : '?';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: _blue.withValues(alpha: 0.12),
        child: Text(initials,
            style: GoogleFonts.barlowCondensed(
                fontSize: 20, fontWeight: FontWeight.w700, color: _blue)),
      ),
      title: Row(children: [
        Expanded(
          child: Text(clientName,
              style: GoogleFonts.barlowCondensed(
                  fontSize: 16,
                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                  color: _text)),
        ),
        Text(timeLabel,
            style: GoogleFonts.barlow(
                fontSize: 11,
                color: unread > 0 ? _blue : _sub,
                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400)),
      ]),
      subtitle: Row(children: [
        Expanded(
          child: Text(lastMsg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                  fontSize: 13,
                  color: unread > 0 ? _text : _sub,
                  fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.w400)),
        ),
        if (unread > 0)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: _blue, borderRadius: BorderRadius.circular(12)),
            child: Text('$unread',
                style: GoogleFonts.barlowCondensed(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
      ]),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminConversationScreen(
            clientUid: doc.id,
            clientName: clientName,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('h:mm a').format(dt.toLocal());
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return DateFormat('EEE').format(dt.toLocal());
    return DateFormat('MMM d').format(dt.toLocal());
  }
}

// ─── Full conversation view for the trainer ──────────────────────────────────

class AdminConversationScreen extends StatefulWidget {
  final String clientUid;
  final String clientName;

  const AdminConversationScreen({
    super.key,
    required this.clientUid,
    required this.clientName,
  });

  @override
  State<AdminConversationScreen> createState() => _AdminConversationScreenState();
}

class _AdminConversationScreenState extends State<AdminConversationScreen> {
  static const _navy    = Color(0xFF1C2D5E);
  static const _blue    = Color(0xFF2563EB);
  static const _bg      = Color(0xFFF5F7FB);
  static const _card    = Color(0xFFFFFFFF);
  static const _text    = Color(0xFF111827);
  static const _sub     = Color(0xFF6B7280);
  static const _divider = Color(0xFFE5E7EB);

  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _fs     = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    final batch = _fs.batch();
    final snap = await _fs
        .collection('messages')
        .doc(widget.clientUid)
        .collection('chat')
        .where('senderId', isNotEqualTo: 'trainer')
        .where('read', isEqualTo: false)
        .get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    if (snap.docs.isNotEmpty) {
      batch.update(
          _fs.collection('messages').doc(widget.clientUid),
          {'unreadByTrainer': 0});
      await batch.commit();
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();

    final now      = FieldValue.serverTimestamp();
    final convRef  = _fs.collection('messages').doc(widget.clientUid);
    final msgRef   = convRef.collection('chat').doc();

    final batch = _fs.batch();
    batch.set(msgRef, {
      'senderId': 'trainer',
      'senderName': 'Kenny',
      'text': text,
      'timestamp': now,
      'read': false,
    });
    batch.set(convRef, {
      'lastMessage': text,
      'lastMessageTime': now,
      'unreadByClient': FieldValue.increment(1),
      'unreadByTrainer': 0,
    }, SetOptions(merge: true));

    await batch.commit();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _blue,
            child: Text(
              widget.clientName.isNotEmpty ? widget.clientName[0].toUpperCase() : '?',
              style: GoogleFonts.barlowCondensed(
                  fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Text(widget.clientName,
              style: GoogleFonts.barlowCondensed(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
      body: Column(children: [
        Expanded(child: _buildMessages()),
        _buildInputBar(),
      ]),
    );
  }

  Widget _buildMessages() {
    return StreamBuilder<QuerySnapshot>(
      stream: _fs
          .collection('messages')
          .doc(widget.clientUid)
          .collection('chat')
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('No messages yet',
                style: GoogleFonts.barlow(fontSize: 14, color: _sub)),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: docs.length,
          itemBuilder: (_, i) => _buildBubble(docs[i]),
        );
      },
    );
  }

  Widget _buildBubble(DocumentSnapshot doc) {
    final d      = doc.data() as Map<String, dynamic>;
    final isMe   = d['senderId'] == 'trainer';
    final text   = d['text'] as String? ?? '';
    final ts     = d['timestamp'] as Timestamp?;
    final time   = ts != null
        ? DateFormat('h:mm a').format(ts.toDate().toLocal())
        : '';

    return Padding(
      padding: EdgeInsets.only(
          top: 3, bottom: 3,
          left: isMe ? 48 : 0,
          right: isMe ? 0 : 48),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.grey.shade200,
                  child: Text(
                    widget.clientName.isNotEmpty ? widget.clientName[0].toUpperCase() : '?',
                    style: GoogleFonts.barlowCondensed(
                        fontSize: 12, fontWeight: FontWeight.w700, color: _navy),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? _blue : _card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: _navy.withValues(alpha: 0.07),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text(text,
                      style: GoogleFonts.barlow(
                          fontSize: 14.5, height: 1.4,
                          color: isMe ? Colors.white : _text)),
                ),
              ),
              if (isMe) const SizedBox(width: 6),
            ],
          ),
          if (time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 34, right: 6),
              child: Text(time,
                  style: GoogleFonts.barlow(fontSize: 10, color: _sub)),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _divider)),
        boxShadow: [
          BoxShadow(
              color: _navy.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16, right: 8, top: 8,
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
              hintText: 'Reply to ${widget.clientName}...',
              hintStyle: GoogleFonts.barlow(fontSize: 14, color: _sub),
              filled: true,
              fillColor: _bg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: _divider)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: _blue, width: 1.5)),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_navy, _blue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
