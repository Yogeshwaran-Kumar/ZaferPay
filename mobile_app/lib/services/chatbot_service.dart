import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class ChatbotService {
  final ApiClient _client = ApiClient();

  /// Sends a message to the cyber complaint chatbot and returns the reply.
  /// [message] is the user's question.
  /// [history] is the conversation history as a list of {role, content} maps.
  Future<String> sendMessage(
    String message,
    List<Map<String, String>> history,
  ) async {
    try {
      final response = await _client.post(
        '/chatbot',
        body: {'message': message, 'history': history},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['reply'] ?? 'Sorry, I could not process your request.';
      } else if (response.statusCode == 503) {
        return 'The chatbot service is currently unavailable. Please try again later.';
      } else {
        if (kDebugMode) {
          print('Chatbot error: ${response.statusCode} - ${response.body}');
        }
        return 'Sorry, something went wrong. Please try again.';
      }
    } catch (e) {
      if (kDebugMode) print('Chatbot service error: $e');
      return 'Unable to connect to the chatbot. Please check your internet connection.';
    }
  }
}
