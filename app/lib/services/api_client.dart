import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../constants.dart';

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isNetworkError;
  final bool isTimeout;

  ApiException(
    this.message, {
    this.statusCode,
    this.isNetworkError = false,
    this.isTimeout = false,
  });

  @override
  String toString() => message;

  /// Get user-friendly message in Japanese
  String get userMessage {
    if (isTimeout) {
      return 'サーバーの応答がありません。しばらくしてから再度お試しください。';
    }
    if (isNetworkError) {
      return 'ネットワークに接続できません。インターネット接続を確認してください。';
    }
    if (statusCode != null) {
      switch (statusCode) {
        case 400:
          return 'リクエストが不正です';
        case 401:
          return '認証エラーが発生しました';
        case 403:
          return 'アクセスが拒否されました';
        case 404:
          return 'リソースが見つかりません';
        case 500:
          return 'サーバーエラーが発生しました';
        case 503:
          return 'サーバーが一時的に利用できません';
        default:
          return 'エラーが発生しました (コード: $statusCode)';
      }
    }
    return message;
  }
}

/// API Client with error handling and timeout support
class ApiClient {
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration longTimeout = Duration(seconds: 60); // For AI generation

  /// Make a GET request
  static Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final url = Uri.parse('$backendUrl$endpoint');
    
    try {
      final response = await http
          .get(url, headers: _defaultHeaders(headers))
          .timeout(timeout ?? defaultTimeout);

      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException('Request timed out', isTimeout: true);
    } on SocketException {
      throw ApiException('No internet connection', isNetworkError: true);
    } catch (e) {
      debugPrint('API GET Error: $e');
      throw ApiException(e.toString());
    }
  }

  /// Make a POST request with JSON body
  static Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final url = Uri.parse('$backendUrl$endpoint');
    
    try {
      final response = await http
          .post(
            url,
            headers: _defaultHeaders(headers, isJson: true),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout ?? defaultTimeout);

      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException('Request timed out', isTimeout: true);
    } on SocketException {
      throw ApiException('No internet connection', isNetworkError: true);
    } catch (e) {
      debugPrint('API POST Error: $e');
      throw ApiException(e.toString());
    }
  }

  /// Make a multipart POST request (for file uploads)
  static Future<Map<String, dynamic>> postMultipart(
    String endpoint, {
    required Map<String, String> fields,
    http.MultipartFile? file,
    Duration? timeout,
  }) async {
    final url = Uri.parse('$backendUrl$endpoint');
    
    try {
      final request = http.MultipartRequest('POST', url);
      request.fields.addAll(fields);
      
      if (file != null) {
        request.files.add(file);
      }

      final streamedResponse = await request.send().timeout(timeout ?? longTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException('Request timed out', isTimeout: true);
    } on SocketException {
      throw ApiException('No internet connection', isNetworkError: true);
    } catch (e) {
      debugPrint('API Multipart Error: $e');
      throw ApiException(e.toString());
    }
  }

  /// Default headers for requests
  static Map<String, String> _defaultHeaders(
    Map<String, String>? custom, {
    bool isJson = false,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    
    if (custom != null) {
      headers.addAll(custom);
    }
    
    return headers;
  }

  /// Handle HTTP response
  static Map<String, dynamic> _handleResponse(http.Response response) {
    debugPrint('API Response [${response.statusCode}]: ${response.body.substring(0, response.body.length.clamp(0, 200))}...');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {};
      }
      
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        // If response is not JSON, wrap it
        return {'data': response.body};
      }
    } else {
      String errorMessage = 'Request failed';
      
      try {
        final errorBody = jsonDecode(response.body);
        errorMessage = errorBody['detail'] ?? errorBody['message'] ?? errorMessage;
      } catch (_) {
        errorMessage = response.body;
      }
      
      throw ApiException(
        errorMessage,
        statusCode: response.statusCode,
      );
    }
  }

  /// Check if backend is reachable
  static Future<bool> healthCheck() async {
    try {
      final url = Uri.parse('$backendUrl/');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }
}
