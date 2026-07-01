import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'config.dart';

class SocketService {
  static IO.Socket? _socket;
  static bool _connected = false;
  static bool _connecting = false; // يمنع اتصالين في نفس الوقت
  static String? _currentToken;

  static IO.Socket _buildSocket(String token) {
    final transports = kIsWeb ? ['polling'] : ['websocket', 'polling'];
    return IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(transports)
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(3000)
          .setAuth({'token': token})
          .build(),
    );
  }

  static IO.Socket get socket {
    assert(_socket != null, 'استدعِ connectWithToken() بعد Login أولاً');
    return _socket!;
  }

  static void connectWithToken(String token) {
    // نفس الـ token ومتصل أو جاري الاتصال → تجاهل
    if (_currentToken == token && (_connected || _connecting)) return;

    // token جديد → انقطع أولاً وأغلق القديم
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _connected = false;
    }

    _currentToken = token;
    _connecting = true;
    _socket = _buildSocket(token);

    _socket!.onConnect((_) {
      _connected = true;
      _connecting = false;
      debugPrint('✅ Socket connected');
    });
    _socket!.onDisconnect((_) {
      _connected = false;
      _connecting = false;
      debugPrint('❌ Socket disconnected');
    });
    _socket!.onConnectError((e) {
      _connecting = false;
      debugPrint('❌ Socket connect error: $e');
    });
    _socket!.onReconnect((_) => debugPrint('🔄 Socket reconnected'));

    _socket!.connect();
  }

  static void disconnect() {
    _socket?.disconnect();
    _connected = false;
  }

  static bool get isConnected => _connected;

  // ===== الراكب ينضم لرحلته =====
  static void joinAsPassenger(int tripId, String userPhone) {
    if (!_connected) return;
    socket.emit('passenger:join', {'tripId': tripId, 'userPhone': userPhone});
    debugPrint('👤 Joining trip:$tripId as passenger');
  }

  // ===== السائق ينضم لرحلته =====
  static void joinAsDriver(int tripId, String driverPhone) {
    if (!_connected) return;
    socket.emit('driver:join', {'tripId': tripId, 'driverPhone': driverPhone});
    debugPrint('🚕 Joining trip:$tripId as driver');
  }

  // ===== السائق يسجّل نفسه online =====
  static void registerDriver() {
    if (!_connected) return;
    socket.emit('driver:register');
    debugPrint('🚗 Driver registered');
  }

  // ===== السائق يرسل موقعه =====
  static void sendDriverLocation(int tripId, double lat, double lng) {
    if (!_connected) return;
    socket.emit('driver:location', {'tripId': tripId, 'lat': lat, 'lng': lng});
  }

  // ===== Listeners =====
  static void onDriverMoved(Function(Map) callback) {
    socket.off('driver:moved');
    socket.on('driver:moved', (data) {
      try {
        callback(Map<String, dynamic>.from(data as Map));
      } catch (e) {
        debugPrint('onDriverMoved error: $e');
      }
    });
  }

  static void onTripUpdated(Function(Map) callback) {
    socket.off('trip:updated');
    socket.on('trip:updated', (data) {
      debugPrint('📨 Socket trip:updated received');
      try {
        callback(Map<String, dynamic>.from(data as Map));
      } catch (e) {
        debugPrint('onTripUpdated error: $e');
      }
    });
  }

  static void onTripAccepted(Function(Map) callback) {
    socket.off('trip:accepted');
    socket.on('trip:accepted', (data) {
      debugPrint('📨 Socket trip:accepted received');
      try {
        callback(Map<String, dynamic>.from(data as Map));
      } catch (e) {
        debugPrint('onTripAccepted error: $e');
      }
    });
  }

  static void onNewTrip(Function(Map) callback) {
    socket.off('new:trip');
    socket.on('new:trip', (data) {
      debugPrint('📨 Socket new:trip received');
      try {
        callback(Map<String, dynamic>.from(data as Map));
      } catch (e) {
        debugPrint('onNewTrip error: $e');
      }
    });
  }

  // ===== Cleanup =====
  static void offDriverMoved() => socket.off('driver:moved');
  static void offTripUpdated() => socket.off('trip:updated');
  static void offNewTrip() => socket.off('new:trip');
  static void offTripAccepted() => socket.off('trip:accepted');

  static void listenToTrip(int tripId, Function(String, Map) callback) {
    socket.off('trip:updated');
    socket.off('trip:accepted');
    socket.off('driver:moved');

    socket.on('trip:updated', (raw) {
      try {
        final data = Map<String, dynamic>.from(raw as Map);
        final id = data['id'] is int
            ? data['id'] as int
            : int.tryParse(data['id']?.toString() ?? '') ?? 0;
        if (id == tripId || id == 0) callback('trip:updated', data);
      } catch (e) {
        debugPrint('listenToTrip error: $e');
      }
    });

    socket.on('trip:accepted', (raw) {
      try {
        final data = Map<String, dynamic>.from(raw as Map);
        final id = data['id'] is int
            ? data['id'] as int
            : int.tryParse(data['id']?.toString() ?? '') ?? 0;
        if (id == tripId || id == 0) callback('trip:accepted', data);
      } catch (e) {
        debugPrint('listenToTrip accepted error: $e');
      }
    });

    socket.on('driver:moved', (raw) {
      try {
        final data = Map<String, dynamic>.from(raw as Map);
        final id = data['tripId'] is int
            ? data['tripId'] as int
            : int.tryParse(data['tripId']?.toString() ?? '') ?? 0;
        if (id == tripId || id == 0) callback('driver:moved', data);
      } catch (e) {
        debugPrint('listenToTrip moved error: $e');
      }
    });
  }

  static void unlistenTrip(int tripId) {
    socket.off('trip:updated');
    socket.off('trip:accepted');
    socket.off('driver:moved');
    debugPrint('🔕 Unlistened trip $tripId');
  }
}
