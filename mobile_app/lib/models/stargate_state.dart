class StargateState {
  final bool wormholeActive;
  final bool lampMode;
  final List<int> lampColor;
  final int lampBrightness;
  final String lampAnimation;
  final bool dialing;
  final int lockedChevrons;

  const StargateState({
    required this.wormholeActive,
    required this.lampMode,
    required this.lampColor,
    required this.lampBrightness,
    required this.lampAnimation,
    required this.dialing,
    required this.lockedChevrons,
  });

  factory StargateState.initial() {
    return const StargateState(
      wormholeActive: false,
      lampMode: false,
      lampColor: [255, 255, 255],
      lampBrightness: 255,
      lampAnimation: 'static',
      dialing: false,
      lockedChevrons: 0,
    );
  }

  factory StargateState.fromJson(Map<String, dynamic> json) {
    List<int> color = [255, 255, 255];
    if (json['lamp_color'] != null) {
      final raw = json['lamp_color'];
      if (raw is List) {
        color = raw.map<int>((e) => (e as num).toInt()).toList();
        if (color.length < 3) color = [255, 255, 255];
      }
    }
    return StargateState(
      wormholeActive: json['wormhole_active'] as bool? ?? false,
      lampMode: json['lamp_mode'] as bool? ?? false,
      lampColor: color,
      lampBrightness: (json['lamp_brightness'] as num?)?.toInt() ?? 255,
      lampAnimation: json['lamp_animation'] as String? ?? 'static',
      dialing: json['dialing'] as bool? ?? false,
      lockedChevrons: (json['locked_chevrons'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wormhole_active': wormholeActive,
      'lamp_mode': lampMode,
      'lamp_color': lampColor,
      'lamp_brightness': lampBrightness,
      'lamp_animation': lampAnimation,
      'dialing': dialing,
      'locked_chevrons': lockedChevrons,
    };
  }

  StargateState copyWith({
    bool? wormholeActive,
    bool? lampMode,
    List<int>? lampColor,
    int? lampBrightness,
    String? lampAnimation,
    bool? dialing,
    int? lockedChevrons,
  }) {
    return StargateState(
      wormholeActive: wormholeActive ?? this.wormholeActive,
      lampMode: lampMode ?? this.lampMode,
      lampColor: lampColor ?? this.lampColor,
      lampBrightness: lampBrightness ?? this.lampBrightness,
      lampAnimation: lampAnimation ?? this.lampAnimation,
      dialing: dialing ?? this.dialing,
      lockedChevrons: lockedChevrons ?? this.lockedChevrons,
    );
  }
}
