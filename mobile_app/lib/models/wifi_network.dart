class WifiNetwork {
  final String ssid;
  final int signal;
  final String security;
  final bool connected;

  const WifiNetwork({
    required this.ssid,
    required this.signal,
    required this.security,
    required this.connected,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid'] as String? ?? '',
      signal: (json['signal'] as num?)?.toInt() ?? 0,
      security: json['security'] as String? ?? 'open',
      connected: json['connected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ssid': ssid,
      'signal': signal,
      'security': security,
      'connected': connected,
    };
  }

  /// Signal strength as 0-4 bars.
  /// Handles both dBm style (-100 to 0) and percentage (0-100).
  int get signalBars {
    // Detect percentage vs dBm
    final s = signal < 0 ? signal : -(100 - signal);
    if (s >= -55) return 4;
    if (s >= -70) return 3;
    if (s >= -80) return 2;
    if (s >= -90) return 1;
    return 0;
  }

  bool get isSecured {
    final sec = security.toLowerCase();
    return sec != 'open' && sec != '' && sec != 'none';
  }

  WifiNetwork copyWith({
    String? ssid,
    int? signal,
    String? security,
    bool? connected,
  }) {
    return WifiNetwork(
      ssid: ssid ?? this.ssid,
      signal: signal ?? this.signal,
      security: security ?? this.security,
      connected: connected ?? this.connected,
    );
  }
}
