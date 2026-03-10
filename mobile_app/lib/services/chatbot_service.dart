import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'app_localizations.dart';

class ChatbotService {
  final ApiClient _client = ApiClient();

  /// Sends a message to the cyber complaint chatbot and returns the reply.
  /// [message] is the user's question.
  /// [history] is the conversation history as a list of {role, content} maps.
  Future<String> sendMessage(
    String message,
    List<Map<String, String>> history,
    BuildContext context,
  ) async {
    final localizations = AppLocalizations.of(context);
    final languageCode = localizations?.locale.languageCode ?? 'en';
    try {
      final response = await _client.post(
        '/chatbot',
        body: {
          'message': message,
          'history': history,
          'language': languageCode,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['reply'] ??
            (localizations?.translate('chatbot.error_processing') ??
                'Sorry, I could not process your request.');
      } else if (response.statusCode == 503) {
        return localizations?.translate('chatbot.error_unavailable') ??
            'The chatbot service is currently unavailable. Please try again later.';
      } else {
        if (kDebugMode) {
          print('Chatbot error: ${response.statusCode} - ${response.body}');
        }
        return localizations?.translate('chatbot.error_generic') ??
            'Sorry, something went wrong. Please try again.';
      }
    } catch (e) {
      if (kDebugMode) print('Chatbot service error: $e');
      return localizations?.translate('chatbot.error_connection') ??
          'Unable to connect to the chatbot. Please check your internet connection.';
    }
  }
}
