import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:get_storage/get_storage.dart';

/// Persistent storage for Cognito session tokens using GetStorage.
class _CognitoSessionStorage extends CognitoStorage {
  final GetStorage _storage = GetStorage('cognito_session');

  @override
  Future<String?> getItem(String key) async {
    return _storage.read(key);
  }

  @override
  Future<void> setItem(String key, value) async {
    await _storage.write(key, value);
  }

  @override
  Future<void> removeItem(String key) async {
    await _storage.remove(key);
  }

  @override
  Future<void> clear() async {
    await _storage.erase();
  }
}

class AuthService {
  static const String userPoolId = 'us-east-1_abgV4lc4K';
  static const String clientId = '52tl33c9nbkcjq2n7tf283te2r';
  static const String region = 'us-east-1';

  static final _cognitoStorage = _CognitoSessionStorage();
  static final CognitoUserPool _userPool =
      CognitoUserPool(userPoolId, clientId, storage: _cognitoStorage);
  static final GetStorage _storage = GetStorage();

  static CognitoUser? _currentUser;
  static CognitoUserSession? _session;

  /// Initialize storage containers (call before runApp).
  static Future<void> init() async {
    await GetStorage.init('cognito_session');
  }

  /// Whether the user is currently logged in (has a valid session).
  static bool get isLoggedIn => _session != null && _session!.isValid();

  /// Get the current user's display name.
  static String get displayName => _storage.read('displayName') ?? 'Player';

  /// Get the current user's email.
  static String get email => _storage.read('email') ?? '';

  /// Get the current user's ID (Cognito sub).
  static String get userId => _storage.read('userId') ?? '';

  /// Get the JWT access token for API calls.
  static String? get accessToken => _session?.getAccessToken().getJwtToken();

  /// Register a new user with email, password, and display name.
  static Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final attributes = [
      AttributeArg(name: 'email', value: email),
      AttributeArg(name: 'name', value: displayName),
    ];

    await _userPool.signUp(email, password, userAttributes: attributes);
  }

  /// Confirm registration with the verification code sent to email.
  static Future<bool> confirmRegistration({
    required String email,
    required String code,
  }) async {
    final user = CognitoUser(email, _userPool, storage: _cognitoStorage);
    return await user.confirmRegistration(code);
  }

  /// Login with email and password.
  static Future<void> login({
    required String email,
    required String password,
  }) async {
    _currentUser = CognitoUser(email, _userPool, storage: _cognitoStorage);
    final authDetails = AuthenticationDetails(username: email, password: password);
    _session = await _currentUser!.authenticateUser(authDetails);

    // Fetch user attributes and store locally
    final attrs = await _currentUser!.getUserAttributes();
    String name = 'Player';
    String sub = '';
    for (final attr in attrs ?? []) {
      if (attr.name == 'name') name = attr.value ?? 'Player';
      if (attr.name == 'sub') sub = attr.value ?? '';
    }

    await _storage.write('displayName', name);
    await _storage.write('email', email);
    await _storage.write('userId', sub);
    await _storage.write('isLoggedIn', true);
  }

  /// Try to restore session from storage (call on app start).
  static Future<bool> tryRestoreSession() async {
    final storedEmail = _storage.read('email');
    if (storedEmail == null || storedEmail.toString().isEmpty) return false;

    // Check if user was previously logged in
    final wasLoggedIn = _storage.read('isLoggedIn') ?? false;
    if (!wasLoggedIn) return false;

    _currentUser = CognitoUser(storedEmail, _userPool, storage: _cognitoStorage);
    try {
      _session = await _currentUser!.getSession();
      return _session != null && _session!.isValid();
    } catch (_) {
      // Session refresh failed — but user data is still stored.
      // Mark as logged out so they re-authenticate next time.
      // But first, check if we simply had no network.
      // Keep user "logged in" based on local storage so UI stays consistent.
      // They'll get prompted to re-auth when making an API call.
      return wasLoggedIn;
    }
  }

  /// Logout the current user.
  static Future<void> logout() async {
    if (_currentUser != null) {
      await _currentUser!.signOut();
    }
    _session = null;
    _currentUser = null;
    await _cognitoStorage.clear();
    await _storage.remove('isLoggedIn');
    await _storage.remove('displayName');
    await _storage.remove('email');
    await _storage.remove('userId');
  }

  /// Resend confirmation code.
  static Future<void> resendConfirmationCode(String email) async {
    final user = CognitoUser(email, _userPool, storage: _cognitoStorage);
    await user.resendConfirmationCode();
  }
}
