/// 认证与用户领域模型（文档 #23 / #54 / #87 / #88）。
library;

/// 登录凭据（仅在内存中短暂存在，禁止持久化明文密码）。
final class AuthCredentials {
  /// 创建登录凭据。
  const AuthCredentials({required this.username, required this.password});

  /// 用户名。
  final String username;

  /// 密码（明文，仅在登录请求构建阶段使用）。
  final String password;

  @override
  String toString() => 'AuthCredentials(username: $username, password: ***)';
}

/// 令牌对（文档 #23）。
final class AuthTokens {
  /// 创建令牌对。
  const AuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.refreshExpiresAt,
  });

  /// 访问令牌。
  final String accessToken;

  /// 刷新令牌。
  final String? refreshToken;

  /// 访问令牌过期时间。
  final DateTime? expiresAt;

  /// 刷新令牌过期时间。
  final DateTime? refreshExpiresAt;

  /// 访问令牌是否已过期（无过期时间视为不过期）。
  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  /// 访问令牌是否需要在 [window] 内刷新（请求驱动刷新，文档 #26 / #27）。
  bool shouldRefreshAt(DateTime now, Duration window) {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    return !expiry.isAfter(now.add(window));
  }

  /// 拷贝并覆盖。
  AuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    DateTime? refreshExpiresAt,
  }) {
    return AuthTokens(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
    );
  }

  @override
  String toString() => 'AuthTokens(accessToken: ***, expiresAt: $expiresAt)';
}

/// 登录用户（文档 #87）。
final class UserProfile {
  /// 创建用户模型。
  const UserProfile({
    required this.id,
    required this.username,
    this.nickname,
    this.avatarUrl,
    this.permissions = const <String>[],
    this.role,
    this.email,
    this.phone,
    this.registeredAt,
    this.lastLoginAt,
    this.enabled = true,
  });

  /// 用户 ID。
  final String id;

  /// 登录名。
  final String username;

  /// 昵称。
  final String? nickname;

  /// 头像地址。
  final Uri? avatarUrl;

  /// 服务端下发的权限列表（客户端只消费，不自行判定，文档 #86）。
  final List<String> permissions;

  /// 角色标识（例如 `ADMIN`）。
  final String? role;

  /// 邮箱。
  final String? email;

  /// 手机号。
  final String? phone;

  /// 注册时间。
  final DateTime? registeredAt;

  /// 最近登录时间。
  final DateTime? lastLoginAt;

  /// 账号是否启用。
  final bool enabled;

  /// 展示名称。
  String get displayName =>
      (nickname?.isNotEmpty ?? false) ? nickname! : username;

  /// 拷贝并覆盖。
  UserProfile copyWith({
    String? id,
    String? username,
    String? nickname,
    Uri? avatarUrl,
    List<String>? permissions,
    String? role,
    String? email,
    String? phone,
    DateTime? registeredAt,
    DateTime? lastLoginAt,
    bool? enabled,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      permissions: permissions ?? this.permissions,
      role: role ?? this.role,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      registeredAt: registeredAt ?? this.registeredAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() => 'UserProfile($id, $username)';
}

/// 会话状态机（文档 #54）。
enum AuthState {
  /// 未知。
  unknown,

  /// 校验中。
  checking,

  /// 已认证。
  authenticated,

  /// 已过期。
  expired,

  /// 未认证。
  unauthenticated,
}

/// 登录会话（文档 #88）：令牌 + 用户 + 服务端。
final class AuthSession {
  /// 创建会话。
  const AuthSession({
    required this.tokens,
    required this.user,
    required this.serverId,
  });

  /// 令牌。
  final AuthTokens tokens;

  /// 当前用户。
  final UserProfile user;

  /// 关联的服务端档案 ID。
  final String serverId;

  /// 拷贝并覆盖。
  AuthSession copyWith({
    AuthTokens? tokens,
    UserProfile? user,
    String? serverId,
  }) {
    return AuthSession(
      tokens: tokens ?? this.tokens,
      user: user ?? this.user,
      serverId: serverId ?? this.serverId,
    );
  }

  @override
  String toString() => 'AuthSession(user: ${user.username}, server: $serverId)';
}

/// 认证结果：令牌 + 用户。
final class AuthResult {
  /// 创建认证结果。
  const AuthResult({required this.tokens, required this.user});

  /// 令牌。
  final AuthTokens tokens;

  /// 用户。
  final UserProfile user;
}
