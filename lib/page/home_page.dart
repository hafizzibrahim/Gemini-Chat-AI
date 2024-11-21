import 'dart:io';
import 'dart:typed_data';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:image_picker/image_picker.dart';
import 'package:retry/retry.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Gemini gemini = Gemini.instance;

  List<ChatMessage> messages = [];

  ChatUser currentUser = ChatUser(id: "0", firstName: "User");
  ChatUser geminiUser = ChatUser(id: "1", firstName: "Gemini");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Gemini Chat"),
      ),
      body: _buildUI(),
    );
  }

  Widget _buildUI() {
    return DashChat(
      inputOptions: InputOptions(trailing: [
        IconButton(onPressed: _sendMediaMessage, icon: const Icon(Icons.image)),
      ]),
      currentUser: currentUser,
      onSend: _sendMessage,
      messages: messages,
    );
  }

  void _sendMessage(ChatMessage chatMessage) async {
    setState(() {
      messages = [chatMessage, ...messages];
    });

    try {
      String question = chatMessage.text;

      List<Uint8List>? images;
      if (chatMessage.medias?.isNotEmpty ?? false) {
        images = [
          File(chatMessage.medias!.first.url).readAsBytesSync(),
        ];
      }

      // Menggunakan retry mechanism untuk mencoba ulang permintaan jika error 503
      try {
        await retry(
              () async {
            gemini.streamGenerateContent(question, images: images).listen((event) {
              // Proses response dari Gemini
              ChatMessage? lastMessage = messages.isNotEmpty ? messages.first : null;
              if (lastMessage != null && lastMessage.user == geminiUser) {
                lastMessage = messages.removeAt(0);
                String response = event.content?.parts?.fold(
                    "", (previous, current) => "$previous${current.text}") ?? "";
                lastMessage.text = response;
                setState(() {
                  messages = [lastMessage!, ...messages];
                });
              } else {
                String response = event.content?.parts?.fold(
                    "", (previous, current) => "$previous${current.text}") ?? "";
                ChatMessage message = ChatMessage(
                    user: geminiUser, createdAt: DateTime.now(), text: response);

                setState(() {
                  messages = [message, ...messages];
                });
              }
            });
          },
          retryIf: (e) => e is GeminiException && e.message is String && (e.message as String).contains('503'),
          maxAttempts: 3, // Maksimal 3 kali percobaan
        );
      } catch (e) {
        if (e is GeminiException) {
          // Memeriksa apakah e.message adalah String dan menangani error 503
          if (e.message is String && (e.message as String).contains('503')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Server Gemini sedang tidak tersedia. Coba lagi nanti.')),
            );
          } else {
            // Tangani error lainnya
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.message}')),
            );
          }
        } else {
          // Tangani error tak terduga
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unexpected error: $e')),
          );
        }
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan saat mengirim pesan: $e')),
      );
    }
  }  

  void _sendMediaMessage() async {
    ImagePicker picker = ImagePicker();
    XFile? file = await picker.pickImage(source: ImageSource.gallery);

    if (file != null) {
      ChatMessage chatMessage = ChatMessage(
          user: currentUser,
          createdAt: DateTime.now(),
          text: "Jelaskan gambar ini?",
          medias: [
            ChatMedia(
              url: file.path,
              fileName: "",
              type: MediaType.image,
            )
          ]);
      _sendMessage(chatMessage);
    }
  }
}
