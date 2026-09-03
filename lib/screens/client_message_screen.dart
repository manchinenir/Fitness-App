import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class ClientMessageScreen extends StatefulWidget {
  const ClientMessageScreen({super.key});

  @override
  State<ClientMessageScreen> createState() => _ClientMessageScreenState();
}

class _ClientMessageScreenState extends State<ClientMessageScreen> {
  static const _navy    = Color(0xFF0A1628);
  static const _blue    = Color(0xFF1565C0);
  static const _sky     = Color(0xFF2196F3);
  static const _bg      = Color(0xFFF5F8FF);
  static const _card    = Color(0xFFFFFFFF);
  static const _text    = Color(0xFF0A1628);
  static const _sub     = Color(0xFF546E7A);
  static const _divider = Color(0xFFDDE6F7);

  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _fs     = FirebaseFirestore.instance;
  final _uid    = FirebaseAuth.instance.currentUser!.uid;

  String _myName = '';

  @override
  void initState() {
    super.initState();
    _loadName();
    _markRead();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    final snap = await _fs.collection('users').doc(_uid).get();
    if (mounted) {
      final d = snap.data() ?? {};
      setState(() {
        _myName = '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
      });
    }
  }

  Future<void> _markRead() async {
    // Mark all client-unread messages (sent by trainer) as read
    final batch = _fs.batch();
    final snap = await _fs
        .collection('messages')
        .doc(_uid)
        .collection('chat')
        .where('senderId', isEqualTo: 'trainer')
        .where('read', isEqualTo: false)
        .get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    if (snap.docs.isNotEmpty) {
      batch.update(_fs.collection('messages').doc(_uid), {'unreadByClient': 0});
      await batch.commit();
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();

    final now = FieldValue.serverTimestamp();
    final convRef = _fs.collection('messages').doc(_uid);
    final msgRef = convRef.collection('chat').doc();

    final batch = _fs.batch();
    batch.set(msgRef, {
      'senderId': _uid,
      'senderName': _myName.isNotEmpty ? _myName : 'Client',
      'text': text,
      'timestamp': now,
      'read': false,
    });
    batch.set(convRef, {
      'clientUid': _uid,
      'clientName': _myName.isNotEmpty ? _myName : 'Client',
      'lastMessage': text,
      'lastMessageTime': now,
      'unreadByTrainer': FieldValue.increment(1),
      'unreadByClient': 0,
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
      appBar: _buildAppBar(),
      body: Column(children: [
        Expanded(child: _buildMessages()),
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
        CircleAvatar(
          radius: 18,
          backgroundColor: _blue,
          child: Text('K',
              style: GoogleFonts.barlowCondensed(
                  fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kenny',
              style: GoogleFonts.barlowCondensed(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          Text('Your Trainer',
              style: GoogleFonts.barlow(fontSize: 11, color: Colors.white60)),
        ]),
      ]),
    );
  }

  Widget _buildMessages() {
    return StreamBuilder<QuerySnapshot>(
      stream: _fs
          .collection('messages')
          .doc(_uid)
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 56, color: _divider),
              const SizedBox(height: 12),
              Text('No messages yet',
                  style: GoogleFonts.barlowCondensed(
                      fontSize: 18, fontWeight: FontWeight.w700, color: _sub)),
              const SizedBox(height: 4),
              Text('Send Kenny a message to get started',
                  style: GoogleFonts.barlow(fontSize: 13, color: _sub)),
            ]),
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
    final d = doc.data() as Map<String, dynamic>;
    final isMe = d['senderId'] != 'trainer';
    final text = d['text'] as String? ?? '';
    final ts = d['timestamp'] as Timestamp?;
    final time = ts != null
        ? DateFormat('h:mm a').format(ts.toDate().toLocal())
        : '';

    return Padding(
      padding: EdgeInsets.only(
        top: 3, bottom: 3,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
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
                  backgroundColor: _blue,
                  child: Text('K',
                      style: GoogleFonts.barlowCondensed(
                          fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
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
              hintText: 'Message Kenny...',
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
