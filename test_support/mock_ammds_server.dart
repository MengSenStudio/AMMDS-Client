import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ammds_client/core/constants/discovery_constants.dart';
import 'package:ammds_client/core/discovery/discovery_codec.dart';
import 'package:ammds_client/core/discovery/discovery_models.dart';
import 'package:ammds_client/core/utils/rsa_crypto.dart';

/// 一个可运行的 AMMDS 服务端测试桩。
///
/// 同时实现：
/// * Client API HTTP 端点（登录 / 刷新 / 会话 / 用户 / 内容）
/// * 发现协议 UDP 端点
/// * 与服务端一致的 RSA 公钥下发（`/api/oauth/secret`）
///
/// 端到端测试用它替代真实服务端，验证客户端「发现 → 登录 → 主界面」链路。
final class MockAmmdsServer {
  MockAmmdsServer({
    this.username = 'admin',
    this.password = 'ammds-secret',
    this.serverName = 'AMMDS Test Server',
    this.serverId = 'test-server-0001',
    this.accessTokenTtl = const Duration(minutes: 30),
    this.enableDiscovery = true,
    this.requirePasswordEncryption = false,
    this.verbose = false,
  });

  /// 正确的用户名。
  final String username;

  /// 正确的密码。
  final String password;

  /// 服务端名称。
  final String serverName;

  /// 服务端 ID。
  final String serverId;

  /// 访问令牌有效期。
  final Duration accessTokenTtl;

  /// 是否启动 UDP 发现端点。
  final bool enableDiscovery;

  /// 是否要求密码必须使用 RSA 公钥加密。
  final bool requirePasswordEncryption;

  /// 是否在标准错误输出每个收到的请求（端到端调试用）。
  final bool verbose;

  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _udpTimer;
  _RsaKeyPair? _keyPair;

  /// 端口。
  int get port => _httpServer?.port ?? 0;

  /// 服务地址（回环，便于测试断言与直接访问）。
  String get baseUrl => 'http://127.0.0.1:$port';

  /// 已签发的访问令牌。
  final Map<String, DateTime> issuedTokens = <String, DateTime>{};

  /// 已签发但被刷新替换的令牌。
  final Set<String> revokedTokens = <String>{};

  /// 登录尝试次数。
  int loginAttempts = 0;

  /// 登录失败次数。
  int loginFailures = 0;

  /// 使用 RSA 加密密码登录的次数。
  int encryptedLoginAttempts = 0;

  /// 收到的发现探测次数。
  int discoveryProbes = 0;

  /// 最近一次登录使用的用户名。
  String? lastLoginUsername;

  /// 当前生成的 RSA 公钥 PEM（测试断言使用）。
  String get publicKeyPem => _keyPair!.publicKeyPem;

  /// 使用服务端私钥校验客户端提交的密文（测试断言使用）。
  String? decryptPassword(String cipherBase64) =>
      _keyPair!.decryptBase64(cipherBase64);

  /// 启动服务端。
  Future<void> start() async {
    _keyPair = _RsaKeyPair.generate();
    // 监听所有网卡：发现协议会上报「报文来源网卡地址」，
    // 若只绑定回环地址，客户端拿到局域网地址后将无法建立连接。
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    unawaited(_serve(_httpServer!));
    if (enableDiscovery) {
      await _startDiscovery();
    }
  }

  /// 停止服务端。
  Future<void> stop() async {
    _udpTimer?.cancel();
    _udpTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  void unawaited(Future<void> future) {
    future.ignore();
  }

  Future<void> _startDiscovery() async {
    // UDP 发现端口只是「可能」被使用的路径：端到端测试通过注入单播探测
    // 目标（127.0.0.1）来发现服务端，无需监听固定端口。
    // 若端口不可用则跳过，避免测试环境差异导致整条链路失败。
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        DiscoveryConstants.port,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _udpSocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }
        discoveryProbes++;
        final payload = _buildDiscoveryResponse(
          host: datagram.address.address == '0.0.0.0'
              ? '127.0.0.1'
              : datagram.address.address,
        );
        socket.send(payload, datagram.address, datagram.port);
      });
    } on Object catch (error) {
      stderr.writeln('mock discovery listener skipped: $error');
    }
  }

  /// 构造发现响应报文（与文档 #17 一致）。
  Uint8List _buildDiscoveryResponse({required String host}) {
    final response = DiscoveryResponse(
      protocol: DiscoveryConstants.protocol,
      version: DiscoveryConstants.version,
      service: DiscoveryConstants.service,
      serverId: serverId,
      name: serverName,
      host: host,
      port: port,
      apiVersion: 'v1',
      https: false,
      versionName: '1.0.0',
      capabilities: const <String, bool>{
        'media': true,
        'people': true,
        'novel': true,
        'comic': true,
      },
    );
    return Uint8List.fromList(DiscoveryCodec.encodeResponse(response));
  }

  /// 主动构造一条发现响应（供测试断言或单播发送）。
  Uint8List discoveryPayload({String host = '127.0.0.1'}) =>
      _buildDiscoveryResponse(host: host);

  /// 直接向本机发现端口发送一次探测（用于验证真实 UDP 链路）。
  Future<bool> probeDiscovery({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    try {
      final completer = Completer<bool>();
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      });
      socket.send(
        Uint8List.fromList(
          DiscoveryCodec.encodeRequest(const DiscoveryRequest()),
        ),
        InternetAddress.loopbackIPv4,
        DiscoveryConstants.port,
      );
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
      await subscription.cancel();
      return result;
    } finally {
      socket.close();
    }
  }

  /// 已保存的阅读进度（键为 `segment:id`），用于端到端验证跨设备续读。
  final Map<String, Map<String, Object?>> _readProgress =
      <String, Map<String, Object?>>{};

  /// 已保存的阅读进度快照，供端到端用例断言（键形如 `novels:novels-1`）。
  Map<String, Map<String, Object?>> get savedReadProgress =>
      Map<String, Map<String, Object?>>.unmodifiable(_readProgress);

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request);
      } on Object catch (error) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } on Object {
          // 连接可能已被客户端关闭。
        }
        stderr.writeln('mock server error: $error');
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (verbose) {
      stderr.writeln('mock server ← ${request.method} $path');
    }

    if (path == '/api/oauth/secret' && request.method == 'GET') {
      return _json(response, <String, Object?>{
        'code': 0,
        'data': <String, Object?>{'publicKey': _keyPair!.publicKeyPem},
      });
    }

    if (path == '/api/client/v1/health') {
      return _json(response, <String, Object?>{'code': 0, 'data': 'ok'});
    }

    if (path == '/api/client/v1/server/info') {
      return _json(response, <String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'server_id': serverId,
          'name': serverName,
          'server_version': '1.0.0',
          'api_version': 'v1',
          'https': false,
          'capabilities': <String, bool>{
            'media': true,
            'people': true,
            'novel': true,
            'comic': true,
          },
        },
      });
    }

    if (path == '/api/client/v1/auth/login') {
      return _handleLogin(request);
    }

    if (path == '/api/client/v1/auth/refresh') {
      return _handleRefresh(request);
    }

    if (path == '/api/client/v1/auth/logout') {
      return _json(response, <String, Object?>{'code': 0, 'data': null});
    }

    if (path == '/api/client/v1/auth/session') {
      return _protected(request, (token) {
        return <String, Object?>{
          'code': 0,
          'data': <String, Object?>{'valid': true},
        };
      });
    }

    if (path == '/api/client/v1/user/profile') {
      return _protected(request, (token) {
        return <String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'id': 'user-1',
            'username': username,
            'nickname': '测试管理员',
            'avatar': null,
            'permissions': <String>['media:read', 'novel:read'],
          },
        };
      });
    }

    // 阅读进度（跨设备续读）：优先于通用的内容路由，否则会被列表规则吃掉。
    final progress = RegExp(
      r'^/api/client/v1/(novels|comics)/([^/]+)/progress$',
    ).firstMatch(path);
    if (progress != null) {
      return _protected(
        request,
        (token) => _readingProgress(
          progress.group(1)!,
          progress.group(2)!,
          request,
        ),
      );
    }

    if (path.startsWith('/api/client/v1/media')) {
      return _protected(request, (token) => _content(request, 'media'));
    }
    if (path.startsWith('/api/client/v1/people')) {
      return _protected(request, (token) => _content(request, 'people'));
    }
    if (path.startsWith('/api/client/v1/novels')) {
      return _protected(request, (token) => _content(request, 'novels'));
    }
    if (path.startsWith('/api/client/v1/comics')) {
      return _protected(request, (token) => _content(request, 'comics'));
    }

    response.statusCode = HttpStatus.notFound;
    return _json(response, <String, Object?>{
      'code': 404,
      'message': 'not found: $path',
    });
  }

  /// 内容接口路由：列表 / 详情 / 章节列表 / 章节正文 / 章节图片。
  Map<String, Object?> _content(HttpRequest request, String segment) {
    final path = request.uri.path;
    // 阅读器接口（小说章节正文 / 漫画章节图片）优先匹配，避免被详情规则吃掉
    final novelChapter = RegExp(
      r'^/api/client/v1/novels/([^/]+)/chapters/([^/]+)$',
    ).firstMatch(path);
    if (novelChapter != null) {
      return _novelChapterContent(
        novelChapter.group(1)!,
        novelChapter.group(2)!,
      );
    }
    final comicChapter = RegExp(
      r'^/api/client/v1/comics/([^/]+)/chapters/([^/]+)$',
    ).firstMatch(path);
    if (comicChapter != null) {
      return _comicChapterPages(
        comicChapter.group(1)!,
        comicChapter.group(2)!,
      );
    }
    final detail = RegExp('^/api/client/v1/$segment/([^/]+)\$').firstMatch(path);
    if (detail != null) {
      return _detail(segment, detail.group(1)!);
    }
    if (path.endsWith('/chapters')) {
      return <String, Object?>{
        'code': 0,
        'data': <Map<String, Object?>>[
          for (var i = 1; i <= 3; i++) _chapter(i),
        ],
      };
    }
    return _list(segment, request);
  }

  /// 章节条目。
  Map<String, Object?> _chapter(int index) => <String, Object?>{
    'id': 'chapter-$index',
    'title': '第 $index 章',
    'index': index,
  };

  /// 小说章节正文（阅读器）。
  Map<String, Object?> _novelChapterContent(String bookId, String chapterId) {
    final index = int.tryParse(chapterId.split('-').last) ?? 1;
    final hasPrev = index > 1;
    final hasNext = index < 3;
    return <String, Object?>{
      'code': 0,
      'data': <String, Object?>{
        'id': chapterId,
        'book_id': bookId,
        'title': '第 $index 章',
        'index': index,
        'content': '<p>第 $index 章正文第一段</p><p>第 $index 章正文第二段</p>',
        'text': '第 $index 章正文第一段\n第 $index 章正文第二段',
        'word_count': 16,
        'has_content': true,
        'from_source': false,
        'prev_id': hasPrev ? 'chapter-${index - 1}' : null,
        'next_id': hasNext ? 'chapter-${index + 1}' : null,
      },
    };
  }

  /// 漫画章节图片（阅读器）。
  Map<String, Object?> _comicChapterPages(
    String albumId,
    String chapterId,
  ) {
    final index = int.tryParse(chapterId.split('-').last) ?? 1;
    final hasPrev = index > 1;
    final hasNext = index < 3;
    return <String, Object?>{
      'code': 0,
      'data': <String, Object?>{
        'chapter_id': chapterId,
        'chapter_title': '第 $index 话',
        'album_id': albumId,
        'index': index,
        'page_count': 2,
        'pages': <Map<String, Object?>>[
          <String, Object?>{'sequence': 1, 'image': '/static/pages/$index-1.png'},
          <String, Object?>{'sequence': 2, 'image': '/static/pages/$index-2.png'},
        ],
        'prev_id': hasPrev ? 'chapter-${index - 1}' : null,
        'next_id': hasNext ? 'chapter-${index + 1}' : null,
      },
    };
  }

  /// 内容详情（含章节目录与扩展属性）。
  Map<String, Object?> _detail(String segment, String id) {
    final kind = switch (segment) {
      'media' => 'Movie',
      'people' => 'Person',
      'novels' => 'Novel',
      _ => 'Comic',
    };
    final readable = segment == 'novels' || segment == 'comics';
    return <String, Object?>{
      'code': 0,
      'data': <String, Object?>{
        'id': id,
        'title': '$kind detail',
        'subtitle': '副标题',
        'cover': '/static/covers/$id.jpg',
        'year': 2024,
        'rating': 8.5,
        'categories': <String>['测试'],
        'overview': '详情简介',
        'episode_count': readable ? 3 : 0,
        'author': segment == 'novels' ? '作者甲' : null,
        'attributes': <String, Object?>{
          if (segment == 'media') 'runtime_minutes': 120,
          if (segment == 'people') 'height_cm': 170,
          if (segment == 'novels') 'publisher': '出版社甲',
          if (segment == 'comics') 'type': '单行本',
        },
        'gallery': <String>['/static/gallery/1.jpg'],
        'related': segment == 'people'
            ? <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'media-1',
                  'title': 'Movie 1',
                  'cover': '/static/covers/media-1.jpg',
                },
              ]
            : <Map<String, Object?>>[],
        'chapters': readable
            ? <Map<String, Object?>>[for (var i = 1; i <= 3; i++) _chapter(i)]
            : <Map<String, Object?>>[],
      },
    };
  }

  /// 分页内容列表。
  Map<String, Object?> _list(String segment, HttpRequest request) {
    // 客户端使用「页码型游标」（cursor 即页码），与服务端分页模型保持一致。
    final pageSize =
        int.tryParse(request.uri.queryParameters['page_size'] ?? '20') ?? 20;
    final page =
        int.tryParse(request.uri.queryParameters['cursor'] ?? '1') ?? 1;
    final keyword = request.uri.queryParameters['keyword'];
    final prefix = switch (segment) {
      'media' => 'Movie',
      'people' => 'Person',
      'novels' => 'Novel',
      _ => 'Comic',
    };
    const totalItems = 45;
    final start = ((page - 1) * pageSize) + 1;
    final end = (start + pageSize - 1).clamp(1, totalItems);
    final items = <Map<String, Object?>>[
      for (var i = start; i <= end; i++)
        <String, Object?>{
          'id': '$segment-$i',
          'title': keyword == null ? '$prefix $i' : '$prefix $i ($keyword)',
          'cover': '/static/covers/$segment-$i.jpg',
          'year': 2000 + i,
          'rating': 5 + i / 10,
          'categories': <String>['测试'],
        },
    ];
    final hasMore = end < totalItems;
    return <String, Object?>{
      'code': 0,
      'data': <String, Object?>{
        'items': items,
        'has_more': hasMore,
        'next_cursor': hasMore ? '${page + 1}' : null,
        'page': page,
        'page_size': pageSize,
        'total': totalItems,
      },
    };
  }

  Future<void> _handleLogin(HttpRequest request) async {
    loginAttempts++;
    final body = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(body);
    final map = decoded is Map ? decoded : const <String, Object?>{};
    final rawUsername = '${map['username'] ?? ''}';
    final rawPassword = '${map['password'] ?? ''}';
    lastLoginUsername = rawUsername;

    String? plainPassword;
    try {
      plainPassword = _keyPair!.decryptBase64(rawPassword);
      if (plainPassword != null) {
        encryptedLoginAttempts++;
      }
    } on Object {
      plainPassword = null;
    }
    plainPassword ??= rawPassword;

    if (rawUsername != username || plainPassword != password) {
      loginFailures++;
      request.response.statusCode = HttpStatus.unauthorized;
      return _json(request.response, <String, Object?>{
        'code': 401,
        'message': '用户名或密码错误',
      });
    }
    if (requirePasswordEncryption && encryptedLoginAttempts == 0) {
      request.response.statusCode = HttpStatus.badRequest;
      return _json(request.response, <String, Object?>{
        'code': 400,
        'message': 'password must be encrypted',
      });
    }

    final token = _issueToken();
    return _json(request.response, <String, Object?>{
      'code': 0,
      'data': <String, Object?>{
        'access_token': token,
        'refresh_token': 'refresh-$token',
        'expires_in': accessTokenTtl.inSeconds,
        'user': <String, Object?>{
          'id': 'user-1',
          'username': username,
          'nickname': '测试管理员',
          'permissions': <String>['media:read'],
        },
      },
    });
  }

  Future<void> _handleRefresh(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(body);
    final map = decoded is Map ? decoded : const <String, Object?>{};
    final refreshToken = '${map['refresh_token'] ?? ''}';
    if (!refreshToken.startsWith('refresh-')) {
      request.response.statusCode = HttpStatus.unauthorized;
      return _json(request.response, <String, Object?>{
        'code': 401,
        'message': 'refresh token invalid',
      });
    }
    final previous = refreshToken.substring('refresh-'.length);
    revokedTokens.add(previous);
    issuedTokens.remove(previous);
    final token = _issueToken();
    return _json(request.response, <String, Object?>{
      'code': 0,
      'data': <String, Object?>{
        'access_token': token,
        'refresh_token': 'refresh-$token',
        'expires_in': accessTokenTtl.inSeconds,
      },
    });
  }

  String _issueToken() {
    final token =
        'access-${DateTime.now().microsecondsSinceEpoch}-'
        '${Random().nextInt(1 << 20)}';
    issuedTokens[token] = DateTime.now().add(accessTokenTtl);
    return token;
  }

  Future<void> _protected(
    HttpRequest request,
    FutureOr<Map<String, Object?>> Function(String token) build,
  ) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final token = header != null && header.startsWith('Bearer ')
        ? header.substring('Bearer '.length)
        : '';
    if (token.isEmpty || revokedTokens.contains(token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      return _json(request.response, <String, Object?>{
        'code': 401,
        'message': 'unauthorized',
      });
    }
    return _json(request.response, await build(token));
  }

  /// 阅读进度：`GET` 读取、`POST` 保存（字段与 Client API 契约一致）。
  Future<Map<String, Object?>> _readingProgress(
    String segment,
    String id,
    HttpRequest request,
  ) async {
    final key = '$segment:$id';
    if (request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      final decoded = body.isEmpty ? null : jsonDecode(body);
      final map = decoded is Map ? decoded : const <String, Object?>{};
      _readProgress[key] = <String, Object?>{
        'chapter_id': map['chapter_id'],
        'chapter_title': map['chapter_title'],
        'chapter_index': map['chapter_index'],
        'percent': map['percent'],
        'page_no': map['page_no'],
        // 服务端审计时间：用本次保存时间近似
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      return <String, Object?>{'code': 0, 'data': true};
    }
    return <String, Object?>{'code': 0, 'data': _readProgress[key]};
  }

  Future<void> _json(HttpResponse response, Object? payload) async {
    response.write(jsonEncode(payload));
    await response.close();
  }
}

/// 测试用 RSA 密钥对（用于验证客户端的密码加密实现）。
final class _RsaKeyPair {
  _RsaKeyPair._(this.modulus, this.exponent, this.privateExponent);

  final BigInt modulus;
  final BigInt exponent;
  final BigInt privateExponent;

  /// 生成一对足够测试使用的密钥（不用于生产环境）。
  factory _RsaKeyPair.generate() {
    final random = Random(20240919);
    BigInt prime(int bits) {
      while (true) {
        // 构造 bits 位候选值：最高位与最低位强制为 1。
        var candidate = BigInt.one;
        for (var i = 0; i < bits - 1; i++) {
          candidate = (candidate << 1) | BigInt.from(random.nextInt(2));
        }
        candidate = (candidate << 1) | BigInt.one;
        if (_isProbablePrime(candidate)) {
          return candidate;
        }
      }
    }

    final p = prime(256);
    final q = prime(256);
    final modulus = p * q;
    final phi = (p - BigInt.one) * (q - BigInt.one);
    const e = 65537;
    final d = _modInverse(BigInt.from(e), phi);
    return _RsaKeyPair._(modulus, BigInt.from(e), d);
  }

  int get byteLength => (modulus.bitLength + 7) >> 3;

  /// PEM 编码的 SubjectPublicKeyInfo。
  String get publicKeyPem {
    final der = _derSequence(<int>[
      ..._derSequence(<int>[
        ..._derOid(<int>[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]),
        ..._derNull(),
      ]),
      ..._derBitString(<int>[
        ..._derSequence(<int>[
          ..._derInteger(modulus),
          ..._derInteger(exponent),
        ]),
      ]),
    ]);
    final body = base64.encode(der);
    final chunks = <String>[];
    for (var i = 0; i < body.length; i += 64) {
      chunks.add(body.substring(i, min(i + 64, body.length)));
    }
    return '-----BEGIN PUBLIC KEY-----\n'
        '${chunks.join('\n')}\n'
        '-----END PUBLIC KEY-----\n';
  }

  /// 使用私钥解密客户端提交的 PKCS#1 v1.5 密文；失败返回 `null`。
  String? decryptBase64(String cipherBase64) {
    final Uint8List cipher;
    try {
      cipher = base64.decode(cipherBase64);
    } on FormatException {
      return null;
    }
    if (cipher.length != byteLength) {
      return null;
    }
    final message = _bytesToBigInt(cipher);
    final plain = _bigIntToBytes(
      message.modPow(privateExponent, modulus),
      byteLength,
    );
    if (plain[0] != 0x00 || plain[1] != 0x02) {
      return null;
    }
    var index = 2;
    while (index < plain.length && plain[index] != 0x00) {
      index++;
    }
    if (index >= plain.length) {
      return null;
    }
    return utf8.decode(plain.sublist(index + 1));
  }

  static List<int> _derSequence(List<int> content) => <int>[
    0x30,
    ..._derLength(content.length),
    ...content,
  ];

  static List<int> _derInteger(BigInt value) {
    var bytes = _bigIntToBytes(value, (value.bitLength + 7) >> 3);
    if (bytes.isEmpty) {
      bytes = Uint8List.fromList(<int>[0]);
    }
    if (bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList(<int>[0, ...bytes]);
    }
    return <int>[0x02, ..._derLength(bytes.length), ...bytes];
  }

  static List<int> _derOid(List<int> content) => <int>[
    0x06,
    ..._derLength(content.length),
    ...content,
  ];

  static List<int> _derNull() => <int>[0x05, 0x00];

  static List<int> _derBitString(List<int> content) => <int>[
    0x03,
    ..._derLength(content.length + 1),
    0x00,
    ...content,
  ];

  static List<int> _derLength(int length) {
    if (length < 0x80) {
      return <int>[length];
    }
    final bytes = <int>[];
    var remaining = length;
    while (remaining > 0) {
      bytes.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    return <int>[0x80 | bytes.length, ...bytes];
  }
}

BigInt _bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final result = Uint8List(length);
  var current = value;
  for (var i = length - 1; i >= 0; i--) {
    result[i] = (current & BigInt.from(0xff)).toInt();
    current = current >> 8;
  }
  return result;
}

BigInt _modInverse(BigInt value, BigInt modulus) {
  var a = value % modulus;
  var b = modulus;
  var x0 = BigInt.zero;
  var x1 = BigInt.one;
  while (a > BigInt.one) {
    final quotient = a ~/ b;
    var temp = b;
    b = a % b;
    a = temp;
    temp = x0;
    x0 = x1 - quotient * x0;
    x1 = temp;
  }
  return x1 < BigInt.zero ? x1 + modulus : x1;
}

bool _isProbablePrime(BigInt value) {
  if (value < BigInt.two) {
    return false;
  }
  for (final small in const <int>[2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]) {
    final divisor = BigInt.from(small);
    if (value == divisor) {
      return true;
    }
    if (value % divisor == BigInt.zero) {
      return false;
    }
  }
  var d = value - BigInt.one;
  var r = 0;
  while (d.isEven) {
    d = d >> 1;
    r++;
  }
  for (final base in const <int>[2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]) {
    var x = BigInt.from(base).modPow(d, value);
    if (x == BigInt.one || x == value - BigInt.one) {
      continue;
    }
    var composite = true;
    for (var i = 0; i < r - 1; i++) {
      x = x.modPow(BigInt.two, value);
      if (x == value - BigInt.one) {
        composite = false;
        break;
      }
    }
    if (composite) {
      return false;
    }
  }
  return true;
}

/// 供测试直接使用客户端公钥解析（确保测试桩与客户端实现互通）。
RsaPublicKey parsePublicKey(String pem) => RsaPublicKey.parse(pem);
