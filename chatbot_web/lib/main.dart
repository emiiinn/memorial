import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MemorialChatApp());
}

class MemorialChatApp extends StatelessWidget {
  const MemorialChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFC8102E);
    const lightBg = Color(0xFFF8FAFC);

    return MaterialApp(
      title: 'Memorial Sağlık Grubu - AI Asistan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
          primary: primaryRed,
          surface: Colors.white,
          background: lightBg,
        ),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
        scaffoldBackgroundColor: lightBg,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? etiket;
  final String? error;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.etiket,
    this.error,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = false;
  bool _isApiConnected = true;
  final String _apiUrl = "http://127.0.0.1:8000/sor";

  final List<String> _quickQuestions = [
    "Toplam kardiyoloji işlem sayısı nedir?",
    "Poliklinik çalışma saatleri nelerdir?",
    "Kardiyoloji doktorları kimlerdir?",
    "Randevu nasıl alabilirim?",
    "Laboratuvar sonuçları nerede açıklanır?",
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text:
            "Merhaba! Ben Memorial Sağlık Grubu Akıllı Medikal Asistanıyım. Hastane işlemleriniz, kardiyoloji verileri ve genel sağlık sorularınız hakkında size yardımcı olabilirim. Nasıl yardımcı olabilirim?",
        isUser: false,
        timestamp: DateTime.now(),
        etiket: "SISTEM",
      ),
    );
    _checkApiStatus();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkApiStatus() async {
    try {
      final response = await http
          .get(Uri.parse("http://127.0.0.1:8000/"))
          .timeout(const Duration(seconds: 3));
      setState(() {
        _isApiConnected = response.statusCode == 200 || response.statusCode == 404;
      });
    } catch (_) {
      setState(() {
        _isApiConnected = true;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? textToSend]) async {
    final text = textToSend ?? _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (textToSend == null) {
      _inputController.clear();
    }

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'soru': text}),
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final String? etiket = data['etiket'];
        final dynamic rawCevap = data['cevap'];
        final String? hata = data['hata'];

        String? cevap;
        if (rawCevap is String) {
          cevap = rawCevap;
        } else if (rawCevap is List) {
          if (rawCevap.isEmpty) {
            cevap = "Sorgu sonucunda kayıt bulunamadı.";
          } else if (rawCevap.first is Map) {
            List<String> items = [];
            for (int i = 0; i < rawCevap.length; i++) {
              final map = rawCevap[i] as Map;
              final entryStr = map.entries.map((e) => "${e.key}: ${e.value}").join(" | ");
              items.add("${i + 1}. $entryStr");
            }
            cevap = items.join("\n");
          } else {
            cevap = rawCevap.map((e) => e.toString()).join("\n");
          }
        } else if (rawCevap != null) {
          cevap = rawCevap.toString();
        }

        if (hata != null && hata.isNotEmpty) {
          _addBotMessage(
            text: "Sorgu işlenirken bir hata oluştu.",
            etiket: etiket,
            error: hata,
          );
        } else if (cevap != null && cevap.isNotEmpty) {
          _addBotMessage(
            text: cevap,
            etiket: etiket ?? "RAG",
          );
        } else {
          _addBotMessage(
            text: "Bu soru için herhangi bir yanıt üretilemedi veya bilgi bulunamadı.",
            etiket: etiket ?? "DIGER",
          );
        }
      } else {
        _addBotMessage(
          text: "Sunucu hatası: HTTP ${response.statusCode}",
          error: "API '${_apiUrl}' adresinden HTTP ${response.statusCode} yanıtı döndürdü.",
        );
      }
    } catch (e) {
      _addBotMessage(
        text: "FastAPI Sunucusuna ulaşılamadı.",
        error: "Lütfen backend API sunucusunun çalıştığından emin olun (http://127.0.0.1:8000/sor).\nDetay: $e",
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _addBotMessage({required String text, String? etiket, String? error}) {
    final botMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
      etiket: etiket,
      error: error,
    );
    setState(() {
      _messages.add(botMessage);
    });
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: Color(0xFFC8102E)),
            SizedBox(width: 8),
            Text("Sohbeti Temizle"),
          ],
        ),
        content: const Text("Tüm sohbet geçmişi silinecektir. Devam etmek istiyor musunuz?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8102E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _messages.clear();
                _messages.add(
                  ChatMessage(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    text: "Sohbet geçmişi temizlendi. Size nasıl yardımcı olabilirim?",
                    isUser: false,
                    timestamp: DateTime.now(),
                    etiket: "SISTEM",
                  ),
                );
              });
            },
            child: const Text("Temizle"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryRed = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(primaryRed),
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: const Color(0xFFFFEBEE), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      if (_isLoading) _buildPendingBanner(primaryRed),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(20),
                          itemCount: _messages.length + (_isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < _messages.length) {
                              return _buildMessageBubble(_messages[index], primaryRed);
                            } else {
                              return _buildWaitingPulseBubble(primaryRed);
                            }
                          },
                        ),
                      ),
                      if (!_isLoading && _messages.length <= 3)
                        _buildQuickQuestionsSection(primaryRed),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildInputBar(primaryRed),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color primaryRed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: const Border(
          bottom: BorderSide(color: Color(0xFFFFCDD2), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryRed, const Color(0xFF900C21)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primaryRed.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      "MEMORIAL",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 1.2,
                        color: primaryRed,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                      ),
                      child: Text(
                        "AI HEALTH RAG",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: primaryRed,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  "Sağlık Grubu Akıllı Medikal & Veri Asistanı",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isApiConnected ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isApiConnected ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isApiConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isApiConnected ? "API Aktif (127.0.0.1:8000)" : "API Bağlantı Hatası",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _isApiConnected ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: "Sohbeti Temizle",
            onPressed: _isLoading ? null : _clearChat,
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B)),
            style: IconButton.styleFrom(
              hoverColor: const Color(0xFFFFEBEE),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingBanner(Color primaryRed) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF1F2),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFFCDD2)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(primaryRed),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "Yapay zeka cevabı bekleniyor... Yeni soru yazımı geçici olarak kilitlendi.",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, Color primaryRed) {
    final isUser = message.isUser;
    final timeStr =
        "${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}";

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFECDD3), width: 1.5),
              ),
              child: Icon(
                Icons.health_and_safety_rounded,
                color: primaryRed,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isUser ? "Siz" : "Memorial AI Asistan",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (!isUser && message.etiket != null) ...[
                      const SizedBox(width: 8),
                      _buildEtiketBadge(message.etiket!),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? primaryRed : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: isUser
                          ? primaryRed
                          : (message.error != null
                              ? const Color(0xFFFECDD3)
                              : const Color(0xFFE2E8F0)),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        message.text,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: isUser ? Colors.white : const Color(0xFF1E293B),
                          fontWeight: isUser ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      if (message.error != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: Color(0xFFDC2626), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  message.error!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryRed,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEtiketBadge(String etiket) {
    Color bg;
    Color fg;
    IconData icon;

    switch (etiket.toUpperCase()) {
      case 'SQL':
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0369A1);
        icon = Icons.dataset_rounded;
        break;
      case 'RAG':
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF047857);
        icon = Icons.find_in_page_rounded;
        break;
      case 'SISTEM':
        bg = const Color(0xFFFFF1F2);
        fg = const Color(0xFFC8102E);
        icon = Icons.verified_user_rounded;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        icon = Icons.label_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 4),
          Text(
            etiket,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingPulseBubble(Color primaryRed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              shape: BoxShape.circle,
              border: Border.all(color: primaryRed, width: 1.5),
            ),
            child: Icon(
              Icons.health_and_safety_rounded,
              color: primaryRed,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: const Color(0xFFFECDD3), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PulsingMedicalIndicator(),
                const SizedBox(width: 12),
                Text(
                  "Yapay Zeka yanıtı hazırlanıyor (RAG / SQL analiz yapılıyor)...",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primaryRed,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQuestionsSection(Color primaryRed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFAFAFA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: primaryRed, size: 16),
              const SizedBox(width: 6),
              const Text(
                "Önerilen Hızlı Sorular:",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickQuestions.map((q) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: Colors.white,
                    surfaceTintColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFFFCDD2)),
                    elevation: 1,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    label: Text(
                      q,
                      style: TextStyle(
                        fontSize: 12,
                        color: primaryRed,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: _isLoading ? null : () => _sendMessage(q),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(Color primaryRed) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              enabled: !_isLoading,
              onSubmitted: _isLoading ? null : (_) => _sendMessage(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: _isLoading
                    ? "Cevap bekleniyor, lütfen bekleyiniz..."
                    : "Memorial RAG sistemine sorunuzu yazın...",
                hintStyle: TextStyle(
                  color: _isLoading ? primaryRed.withOpacity(0.6) : Colors.grey.shade400,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: _isLoading ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
                prefixIcon: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: _isLoading ? primaryRed : const Color(0xFF94A3B8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: primaryRed, width: 2),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Color(0xFFFECDD3)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inputController,
            builder: (context, value, child) {
              final canSend = !_isLoading && value.text.trim().isNotEmpty;

              return Container(
                decoration: BoxDecoration(
                  gradient: canSend
                      ? LinearGradient(
                          colors: [primaryRed, const Color(0xFF900C21)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: canSend ? null : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                  boxShadow: canSend
                      ? [
                          BoxShadow(
                            color: primaryRed.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: IconButton(
                  iconSize: 22,
                  icon: _isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(primaryRed),
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  color: canSend ? Colors.white : const Color(0xFF94A3B8),
                  onPressed: canSend ? () => _sendMessage() : null,
                  tooltip: _isLoading ? "Yanıt bekleniyor" : "Soru Gönder",
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class PulsingMedicalIndicator extends StatefulWidget {
  const PulsingMedicalIndicator({super.key});

  @override
  State<PulsingMedicalIndicator> createState() => _PulsingMedicalIndicatorState();
}

class _PulsingMedicalIndicatorState extends State<PulsingMedicalIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFC8102E);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            double value = (_controller.value - delay) % 1.0;
            if (value < 0) value += 1.0;

            final scale = 0.5 + (0.5 * (1.0 - (value - 0.5).abs() * 2));
            final opacity = 0.3 + (0.7 * (1.0 - (value - 0.5).abs() * 2));

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 9 * scale,
              height: 9 * scale,
              decoration: BoxDecoration(
                color: color.withOpacity(opacity.clamp(0.2, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
