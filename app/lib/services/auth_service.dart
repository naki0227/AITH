import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
// import 'package:sign_in_with_apple/sign_in_with_apple.dart'; // Standard package but firebase_auth handles provider directly often


/// Service class to handle Firebase Authentication
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get current user ID (returns 'demo_user' if not logged in for backward compatibility)
  String get userId => currentUser?.uid ?? 'demo_user';

  /// Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  /// Sign in with email and password
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign in error: ${e.message}');
      rethrow;
    }
  }

  /// Register with email and password
  Future<UserCredential?> registerWithEmail(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Registration error: ${e.message}');
      rethrow;
    }
  }

  /// Sign in anonymously (for demo/guest mode)
  Future<UserCredential?> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      debugPrint('Anonymous sign in error: ${e.message}');
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        return await _auth.signInWithPopup(googleProvider);
      } else {
        // Native (Android/iOS)
        final GoogleSignIn googleSignIn = GoogleSignIn();
        
        // Ensure previous session is cleared
        await googleSignIn.signOut();
        
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) return null; // User canceled

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        return await _auth.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign in error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Google sign in general error: $e');
      throw FirebaseAuthException(code: 'google-sign-in-failed', message: e.toString());
    }
  }

  /// Sign in with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      final appleProvider = AppleAuthProvider();
      if (kIsWeb) {
        return await _auth.signInWithPopup(appleProvider);
      } else {
        return await _auth.signInWithProvider(appleProvider);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Apple sign in error: ${e.message}');
      rethrow;
    } catch (e) {
       debugPrint('Apple sign in general error: $e');
       throw FirebaseAuthException(code: 'apple-sign-in-failed', message: e.toString());
    }
  }

  /// Get error message in Japanese
  String getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'このメールアドレスは登録されていません';
      case 'wrong-password':
        return 'パスワードが間違っています';
      case 'email-already-in-use':
        return 'このメールアドレスは既に使用されています';
      case 'weak-password':
        return 'パスワードが弱すぎます（6文字以上必要）';
      case 'invalid-email':
        return 'メールアドレスの形式が正しくありません';
      case 'network-request-failed':
        return 'ネットワークエラーが発生しました';
      case 'google-sign-in-failed':
        return 'Googleログインに失敗しました';
      case 'apple-sign-in-failed':
        return 'Appleログインに失敗しました';
      case 'credential-already-in-use':
        return 'このアカウントは既に他のユーザーに関連付けられています';
      default:
        return 'エラーが発生しました: ${e.message}';
    }
  }
}

/// Global auth service instance
final authService = AuthService();
