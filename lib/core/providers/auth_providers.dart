import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

/// Streams every auth state change (sign-in, sign-out, token refresh, etc.).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// The currently signed-in Supabase user, or null when signed out.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider); // rebuild whenever auth changes
  return ref.watch(authServiceProvider).currentUser;
});

/// The current access token, or null when signed out.
final authTokenProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider); // rebuild whenever auth changes
  return ref.watch(authServiceProvider).accessToken;
});
