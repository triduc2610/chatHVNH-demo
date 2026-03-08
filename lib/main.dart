import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Connect to Firebase
  );
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MessageScreen(),
  ));
}

class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key});

  final String currentUserId = "my_user_id";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Tin nhắn", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Gần đây", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
            ),
          ),
          SizedBox(
            height: 100,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .orderBy('lastTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String name = data['name'] ?? "User";
                    String? avatarUrl = data['avatarUrl'];

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ChatDetailScreen(name: name, chatId: docs[index].id)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? const Icon(Icons.person, color: Colors.grey, size: 35)
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              name.split(" ").last,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Align(alignment: Alignment.centerLeft, child: Text("Đoạn chat gần đây", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .orderBy('lastTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final chatDocs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: chatDocs.length,
                  itemBuilder: (context, index) {
                    var data = chatDocs[index].data() as Map<String, dynamic>;

                    dynamic lastTime = data['lastTime'];
                    bool isRead = data['isRead'] ?? true;
                    String lastSenderId = data['lastSenderId'] ?? "";

                    return _buildChatTile(
                        context,
                        data['name'] ?? "User",
                        data['lastMessage'] ?? "",
                        chatDocs[index].id,
                        data['avatarUrl'],
                        lastTime,
                        isRead,
                        lastSenderId,
                        currentUserId
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(BuildContext context, String name,
      String msg,
      String chatId,
      String? avatarUrl,
      dynamic lastTime,
      bool isRead,
      String lastSenderId,
      String currentUserId) {
    String timeStr = "";
    if (lastTime != null && lastTime is Timestamp) {
      DateTime date = lastTime.toDate();
      timeStr = DateFormat('HH:mm').format(date);
    }

    bool isUnreadFromOthers = (lastSenderId != currentUserId) && (isRead == false);
    Color themeColor = isUnreadFromOthers ? const Color(0xFF1A237E) : Colors.black;
    FontWeight textWeight = isUnreadFromOthers ? FontWeight.bold : FontWeight.normal;

    return ListTile(
      leading: CircleAvatar(
        radius: 25,
        backgroundColor: Colors.grey[200],
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
        child: (avatarUrl == null || avatarUrl.isEmpty) ? const Icon(Icons.person) : null,
      ),
      title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: themeColor)),
      subtitle: Text(msg,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: themeColor, fontWeight: textWeight)),
      trailing: Text(timeStr, style: TextStyle(color: themeColor, fontSize: 12)),
      onTap: () {
        FirebaseFirestore.instance.collection('chats').doc(chatId).update({'isRead': true});

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatDetailScreen(name: name, chatId: chatId)),
        );
      },
    );
  }
}

class ChatDetailScreen extends StatefulWidget {
  final String name;
  final String chatId;
  const ChatDetailScreen({super.key, required this.name, required this.chatId});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final String currentUserId = "my_user_id";
  @override
  void initState(){
    super.initState();
    syncLastMessage(widget.chatId);
  }
  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    String text = _controller.text.trim();
    _controller.clear();

    var serverTime = FieldValue.serverTimestamp();

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      DocumentReference newMessageRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      batch.set(newMessageRef, {
        'text': text,
        'senderId': currentUserId,
        'createdAt': serverTime,
      });

      DocumentReference chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);

      batch.update(chatRef, {
        'lastMessage': text,
        'lastTime': serverTime,
        'lastSenderId': currentUserId,
        'isRead': false,
      });

      await batch.commit();

    } catch (e) {
      print("$e");
    }
  }

  Future<void> syncLastMessage(String chatId) async {
    var latestMsgQuery = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (latestMsgQuery.docs.isNotEmpty) {
      var lastData = latestMsgQuery.docs.first.data();

      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'lastMessage': lastData['text'],
        'lastTime': lastData['createdAt'],
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var data = messages[index].data() as Map<String, dynamic>;

                    return _buildBubble(
                        data['text'],
                        data['senderId'] == currentUserId,
                        data['createdAt']
                    );
                  },
                );
              },
            ),
          ),
          _buildInputArea()
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 30),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline, color: Color(0xFF1A237E)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: "Nhập tin nhắn...", border: InputBorder.none),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Color(0xFF1A237E)),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(String text, bool isMe, dynamic createdAt) {
    String timeStr = "";
    if (createdAt != null && createdAt is Timestamp) {
      timeStr = DateFormat('HH:mm').format(createdAt.toDate());
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
            decoration: BoxDecoration(
              color: isMe ? Colors.grey[200] : const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(text, style: TextStyle(color: isMe ? Colors.black : Colors.white)),
          ),
          // HIỂN THỊ THỜI GIAN NHỎ DƯỚI KHUNG CHAT
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}