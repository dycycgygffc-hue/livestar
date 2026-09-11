import 'dart:convert';
import 'package:http/http.dart' as http;

class LiveKitSession {
  final String url;
  final String token;
  final bool isHost;
  LiveKitSession({required this.url, required this.token, required this.isHost});
}

class LiveKitService {
  final String apiBase;
  final String jwt;
  LiveKitService({required this.apiBase, required this.jwt});

  Future<LiveKitSession> token(String roomId, {bool publish = false}) async {
    final r = await http.post(
      Uri.parse('$apiBase/rooms/$roomId/livekit-token'),
      headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'},
      body: jsonEncode({'publish': publish}),
    );
    if (r.statusCode >= 400) throw Exception('LIVEKIT_TOKEN_FAILED');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return LiveKitSession(url: j['url'], token: j['token'], isHost: j['isHost'] == true);
  }
}
