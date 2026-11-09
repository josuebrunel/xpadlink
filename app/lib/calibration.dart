import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';
import 'protocol.dart';
import 'theme.dart';

const _stickMax = 32767;

/// Triggers and sticks of one physical pad. Defaults pass values through, apart from
/// the 8% stick deadzone the app always had.
class PadCalibration {
  PadCalibration({
    this.ltMin = 0,
    this.ltMax = 255,
    this.rtMin = 0,
    this.rtMax = 255,
    this.lcx = 0,
    this.lcy = 0,
    this.lrx = _stickMax,
    this.lry = _stickMax,
    this.rcx = 0,
    this.rcy = 0,
    this.rrx = _stickMax,
    this.rry = _stickMax,
    this.deadzone = 0.08,
  });

  int ltMin, ltMax, rtMin, rtMax;
  int lcx, lcy, lrx, lry; // left stick center and reach per axis
  int rcx, rcy, rrx, rry;
  double deadzone;

  /// A trigger that rests at [min] and tops out at [max] becomes 0..255.
  static int trigger(int raw, int min, int max) {
    if (max - min < 32) return raw; // not a usable range, leave it alone
    return ((raw - min) * 255 / (max - min)).round().clamp(0, 255);
  }

  int lt(int raw) => trigger(raw, ltMin, ltMax);
  int rt(int raw) => trigger(raw, rtMin, rtMax);

  /// One stick axis: recenter, rescale to the measured reach, then apply the deadzone.
  int stick(int raw, int center, int reach) {
    final r = reach < 4096 ? _stickMax : reach;
    final v = ((raw - center) / r).clamp(-1.0, 1.0);
    if (v.abs() < deadzone) return 0;
    return (v * _stickMax).round();
  }

  int lx(int raw) => stick(raw, lcx, lrx);
  int ly(int raw) => stick(raw, lcy, lry);
  int rx(int raw) => stick(raw, rcx, rrx);
  int ry(int raw) => stick(raw, rcy, rry);

  Map<String, dynamic> toJson() => {
        'ltMin': ltMin, 'ltMax': ltMax, 'rtMin': rtMin, 'rtMax': rtMax,
        'lcx': lcx, 'lcy': lcy, 'lrx': lrx, 'lry': lry,
        'rcx': rcx, 'rcy': rcy, 'rrx': rrx, 'rry': rry,
        'deadzone': deadzone,
      };

  factory PadCalibration.fromJson(Map<String, dynamic> j) {
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    return PadCalibration(
      ltMin: i('ltMin', 0), ltMax: i('ltMax', 255),
      rtMin: i('rtMin', 0), rtMax: i('rtMax', 255),
      lcx: i('lcx', 0), lcy: i('lcy', 0), lrx: i('lrx', _stickMax), lry: i('lry', _stickMax),
      rcx: i('rcx', 0), rcy: i('rcy', 0), rrx: i('rrx', _stickMax), rry: i('rry', _stickMax),
      deadzone: (j['deadzone'] as num?)?.toDouble() ?? 0.08,
    );
  }
}

/// Gyro zero point and the roll direction, for the phone's own sensors.
class MotionCalibration {
  MotionCalibration({List<double>? gyroBias, this.flipRoll = false})
      : gyroBias = gyroBias ?? [0, 0, 0];

  List<double> gyroBias; // deg/s
  bool flipRoll;

  /// Cemu reads roll mirrored on some setups: negate accel x and gyro z (the axis
  /// toward the player) to flip left and right.
  PadMotion apply(PadMotion m) {
    final a = List<double>.of(m.accel);
    final g = [for (var i = 0; i < 3; i++) m.gyro[i] - gyroBias[i]];
    if (flipRoll) {
      a[0] = -a[0];
      g[2] = -g[2];
    }
    return PadMotion(a, g);
  }

  Map<String, dynamic> toJson() => {'gyroBias': gyroBias, 'flipRoll': flipRoll};

  factory MotionCalibration.fromJson(Map<String, dynamic> j) => MotionCalibration(
        gyroBias: (j['gyroBias'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        flipRoll: (j['flipRoll'] as bool?) ?? false,
      );
}

/// Calibration lives on the phone: one entry per pad name, one for the phone's motion.
class CalibrationStore {
  static String _padKey(String name) => 'cal.pad.$name';
  static const _motionKey = 'cal.motion';

  Future<PadCalibration> loadPad(String name) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_padKey(name));
    if (raw == null) return PadCalibration();
    try {
      return PadCalibration.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return PadCalibration(); // a bad entry falls back to defaults
    }
  }

  Future<void> savePad(String name, PadCalibration c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_padKey(name), jsonEncode(c.toJson()));
  }

  Future<void> resetPad(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_padKey(name));
  }

  Future<MotionCalibration> loadMotion() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_motionKey);
    if (raw == null) return MotionCalibration();
    try {
      return MotionCalibration.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return MotionCalibration();
    }
  }

  Future<void> saveMotion(MotionCalibration c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_motionKey, jsonEncode(c.toJson()));
  }

  Future<void> resetMotion() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_motionKey);
  }
}

/// Guided calibration: triggers, sticks and motion, each with its own Save.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.padName});

  /// The physical pad that has been sending input, or null when there is none.
  final String? padName;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static final _log = Log('calibration');
  static const _padChannel = EventChannel('xpadlink/gamepad');
  static const _motionChannel = EventChannel('xpadlink/motion');

  final _store = CalibrationStore();
  StreamSubscription<dynamic>? _padSub;
  StreamSubscription<dynamic>? _motionSub;
  Timer? _tick;

  int _tab = 0;
  String? _padName;
  PadCalibration _pad = PadCalibration();
  MotionCalibration _motion = MotionCalibration();

  // Live raw readings.
  int _lt = 0, _rt = 0, _lx = 0, _ly = 0, _rx = 0, _ry = 0;
  List<double> _gyro = [0, 0, 0];

  // Trigger session: the lowest and highest values seen since the last reset.
  int _ltLo = 255, _ltHi = 0, _rtLo = 255, _rtHi = 0;

  // Stick session: the center taken on "Set center" and the farthest reach seen.
  int _lcx = 0, _lcy = 0, _rcx = 0, _rcy = 0;
  int _lrx = 0, _lry = 0, _rrx = 0, _rry = 0;
  bool _centered = false;

  // Gyro bias sampling.
  bool _sampling = false;
  final _gyroSum = [0.0, 0.0, 0.0];
  int _gyroN = 0;
  double _sampleProgress = 0;
  String _saved = '';

  @override
  void initState() {
    super.initState();
    _padName = widget.padName;
    final name = _padName;
    if (name != null) {
      _store.loadPad(name).then((c) {
        if (mounted) setState(() => _pad = c);
      });
    }
    _store.loadMotion().then((c) {
      if (mounted) setState(() => _motion = c);
    });
    _padSub = _padChannel.receiveBroadcastStream().listen(_onPad,
        onError: (Object e) => _log.e('gamepad channel error', e));
    _motionSub = _motionChannel.receiveBroadcastStream().listen(_onMotion,
        onError: (Object e) => _log.e('motion channel error', e));
    _tick = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _padSub?.cancel();
    _motionSub?.cancel();
    super.dispose();
  }

  void _onPad(dynamic event) {
    final m = Map<String, dynamic>.from(event as Map);
    _lt = m['lt'] as int;
    _rt = m['rt'] as int;
    _lx = m['lx'] as int;
    _ly = m['ly'] as int;
    _rx = m['rx'] as int;
    _ry = m['ry'] as int;
    _ltLo = math.min(_ltLo, _lt);
    _ltHi = math.max(_ltHi, _lt);
    _rtLo = math.min(_rtLo, _rt);
    _rtHi = math.max(_rtHi, _rt);
    if (_centered) {
      _lrx = math.max(_lrx, (_lx - _lcx).abs());
      _lry = math.max(_lry, (_ly - _lcy).abs());
      _rrx = math.max(_rrx, (_rx - _rcx).abs());
      _rry = math.max(_rry, (_ry - _rcy).abs());
    }
    _padName ??= m['name'] as String?;
    if (_padName != null && widget.padName == null && _pad.ltMax == 255 && _pad.ltMin == 0) {
      // First input from a pad we hadn't seen: pull its saved values in.
      final name = _padName!;
      _store.loadPad(name).then((c) {
        if (mounted) setState(() => _pad = c);
      });
    }
  }

  void _onMotion(dynamic event) {
    final v = (event as List).cast<double>();
    _gyro = v.sublist(3, 6);
    if (_sampling) {
      for (var i = 0; i < 3; i++) {
        _gyroSum[i] += _gyro[i];
      }
      _gyroN++;
    }
  }

  void _flash(String msg) {
    setState(() => _saved = msg);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = '');
    });
  }

  // Triggers

  void _resetTriggerSession() => setState(() {
        _ltLo = _lt;
        _ltHi = _lt;
        _rtLo = _rt;
        _rtHi = _rt;
      });

  Future<void> _saveTriggers() async {
    final name = _padName;
    if (name == null) return;
    if (_ltHi - _ltLo >= 32) {
      _pad.ltMin = _ltLo;
      _pad.ltMax = _ltHi;
    }
    if (_rtHi - _rtLo >= 32) {
      _pad.rtMin = _rtLo;
      _pad.rtMax = _rtHi;
    }
    await _store.savePad(name, _pad);
    _log.i('triggers saved for $name: lt ${_pad.ltMin}..${_pad.ltMax} rt ${_pad.rtMin}..${_pad.rtMax}');
    _flash('Triggers saved');
  }

  // Sticks

  void _setCenter() => setState(() {
        _lcx = _lx;
        _lcy = _ly;
        _rcx = _rx;
        _rcy = _ry;
        _lrx = _lry = _rrx = _rry = 0;
        _centered = true;
      });

  Future<void> _saveSticks() async {
    final name = _padName;
    if (name == null) return;
    if (_centered) {
      _pad.lcx = _lcx;
      _pad.lcy = _lcy;
      _pad.rcx = _rcx;
      _pad.rcy = _rcy;
      if (_lrx > 4096) _pad.lrx = _lrx;
      if (_lry > 4096) _pad.lry = _lry;
      if (_rrx > 4096) _pad.rrx = _rrx;
      if (_rry > 4096) _pad.rry = _rry;
    }
    await _store.savePad(name, _pad);
    _log.i('sticks saved for $name');
    _flash('Sticks saved');
  }

  // Motion

  Future<void> _measureGyro() async {
    if (_sampling) return;
    _gyroSum.fillRange(0, 3, 0);
    _gyroN = 0;
    setState(() {
      _sampling = true;
      _sampleProgress = 0;
    });
    const total = 2000;
    for (var t = 0; t < total; t += 100) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() => _sampleProgress = (t + 100) / total);
    }
    if (_gyroN > 0) {
      _motion.gyroBias = [for (final s in _gyroSum) s / _gyroN];
    }
    setState(() => _sampling = false);
  }

  Future<void> _saveMotion() async {
    await _store.saveMotion(_motion);
    _log.i('motion saved: bias ${_motion.gyroBias} flip ${_motion.flipRoll}');
    _flash('Motion saved');
  }

  Future<void> _reset() async {
    final name = _padName;
    if (_tab == 2) {
      await _store.resetMotion();
      setState(() => _motion = MotionCalibration());
    } else if (name != null) {
      await _store.resetPad(name);
      setState(() {
        _pad = PadCalibration();
        _centered = false;
      });
    }
    _flash('Reset');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: ConsoleBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _header(),
              const SizedBox(height: 10),
              _tabs(),
              const SizedBox(height: 12),
              Expanded(child: SingleChildScrollView(child: _body())),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(children: [
        BarButton(
          icon: Icons.chevron_left,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Text('CALIBRATION', style: display(15, spacing: 1.8)),
        const SizedBox(width: 12),
        Tag(_padName ?? 'No pad yet', color: _padName != null ? C.lime : C.mute),
        const Spacer(),
        if (_saved.isNotEmpty) Text(_saved, style: mono(12, color: C.lime)),
      ]);

  Widget _tabs() {
    const names = ['TRIGGERS', 'STICKS', 'MOTION'];
    return Row(children: [
      for (var i = 0; i < names.length; i++) ...[
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tab == i ? C.lime : C.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _tab == i ? C.lime : C.line),
              ),
              child: Text(names[i],
                  style: mono(12, color: _tab == i ? C.bg : C.mute, w: FontWeight.w500, spacing: 1)),
            ),
          ),
        ),
        if (i < names.length - 1) const SizedBox(width: 6),
      ],
    ]);
  }

  Widget _body() {
    if (_tab != 2 && _padName == null) {
      return _card([
        Text('Connect a controller', style: display(16)),
        Text('Press any button on your pad. Its readings show up here as soon as it sends input.',
            style: mono(12)),
      ]);
    }
    switch (_tab) {
      case 0:
        return _triggers();
      case 1:
        return _sticks();
      default:
        return _motionTab();
    }
  }

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              children[i],
            ],
          ],
        ),
      );

  Widget _button(String label, VoidCallback? onTap, {bool primary = false}) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? C.lime : C.panel2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary ? C.lime : C.line),
            ),
            child: Text(label, style: display(13, color: primary ? C.bg : C.ink, spacing: 1.2)),
          ),
        ),
      );

  Widget _meter(String label, int raw, int lo, int hi, int out) {
    final span = math.max(hi - lo, 0);
    return _card([
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: display(14)),
        Text('raw $raw  ->  $out', style: mono(12, color: C.ink)),
      ]),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 16,
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(
                color: C.panel2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: C.line),
              ),
            ),
            Container(
              width: w * raw / 255,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [C.violet, C.cyan]),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Positioned(left: w * lo / 255, top: 0, bottom: 0, child: Container(width: 2, color: C.lime)),
            Positioned(left: w * hi / 255 - 2, top: 0, bottom: 0, child: Container(width: 2, color: C.lime)),
          ]),
        );
      }),
      Text('min $lo   max $hi   range $span', style: mono(12)),
    ]);
  }

  Widget _triggers() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pull both triggers all the way, then let go', style: display(18)),
        const SizedBox(height: 4),
        Text('Pull slowly to the end so the app learns your pad\'s range. Hall effect triggers rarely reach 100%.',
            style: mono(12)),
        const SizedBox(height: 12),
        _meter('LT', _lt, _ltLo, _ltHi, _pad.lt(_lt)),
        _meter('RT', _rt, _rtLo, _rtHi, _pad.rt(_rt)),
        Text('Saved range: LT ${_pad.ltMin}..${_pad.ltMax}   RT ${_pad.rtMin}..${_pad.rtMax}', style: mono(12)),
        const SizedBox(height: 12),
        Row(children: [
          _button('START OVER', _resetTriggerSession),
          const SizedBox(width: 8),
          _button('RESET', _reset),
          const SizedBox(width: 8),
          _button('SAVE TRIGGERS', _saveTriggers, primary: true),
        ]),
      ]);

  Widget _stickPad(String label, int x, int y, int cx, int cy) {
    const size = 140.0;
    final dx = x / _stickMax, dy = y / _stickMax;
    return Column(children: [
      Text(label, style: display(13)),
      const SizedBox(height: 6),
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: C.panel,
          border: Border.all(color: C.line),
        ),
        child: Stack(children: [
          Center(
            child: Container(
              width: size * _pad.deadzone * 2,
              height: size * _pad.deadzone * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C.y.withAlpha(24),
                border: Border.all(color: C.y.withAlpha(120)),
              ),
            ),
          ),
          Align(
            alignment: Alignment(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0)),
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Text('raw ${dx.toStringAsFixed(2)} ${dy.toStringAsFixed(2)}', style: mono(11, color: C.ink)),
      Text('center ${(cx / _stickMax).toStringAsFixed(2)} ${(cy / _stickMax).toStringAsFixed(2)}', style: mono(11)),
    ]);
  }

  Widget _sticks() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Release the sticks, then spin each one', style: display(18)),
        const SizedBox(height: 4),
        Text('Tap Set center with both sticks at rest, then spin them around the edge so the reach is measured.',
            style: mono(12)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _stickPad('LEFT', _lx, _ly, _centered ? _lcx : _pad.lcx, _centered ? _lcy : _pad.lcy),
          _stickPad('RIGHT', _rx, _ry, _centered ? _rcx : _pad.rcx, _centered ? _rcy : _pad.rcy),
        ]),
        const SizedBox(height: 12),
        if (_centered)
          Text(
            'Reach  L ${(_lrx / _stickMax).toStringAsFixed(2)} ${(_lry / _stickMax).toStringAsFixed(2)}'
            '   R ${(_rrx / _stickMax).toStringAsFixed(2)} ${(_rry / _stickMax).toStringAsFixed(2)}',
            style: mono(12),
          ),
        const SizedBox(height: 6),
        _card([
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Deadzone', style: display(13)),
            Text('${(_pad.deadzone * 100).round()}%', style: mono(12, color: C.ink)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: C.lime, thumbColor: C.lime),
            child: Slider(
              value: _pad.deadzone,
              max: 0.25,
              divisions: 25,
              onChanged: (v) => setState(() => _pad.deadzone = v),
            ),
          ),
        ]),
        Row(children: [
          _button('SET CENTER', _setCenter),
          const SizedBox(width: 8),
          _button('RESET', _reset),
          const SizedBox(width: 8),
          _button('SAVE STICKS', _saveSticks, primary: true),
        ]),
      ]);

  Widget _motionTab() {
    final b = _motion.gyroBias;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Lay the phone flat and keep it still', style: display(18)),
      const SizedBox(height: 4),
      Text('Two seconds of readings set the gyro zero point, so the cursor stops drifting.', style: mono(12)),
      const SizedBox(height: 12),
      _card([
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Gyro bias', style: display(14)),
          Text('${b[0].toStringAsFixed(3)}  ${b[1].toStringAsFixed(3)}  ${b[2].toStringAsFixed(3)}',
              style: mono(12, color: C.ink)),
        ]),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _sampling ? _sampleProgress : 0,
            minHeight: 12,
            color: C.cyan,
            backgroundColor: C.panel2,
          ),
        ),
        Text('Live gyro  ${_gyro[0].toStringAsFixed(2)}  ${_gyro[1].toStringAsFixed(2)}  ${_gyro[2].toStringAsFixed(2)} deg/s',
            style: mono(12)),
      ]),
      _card([
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Flip roll (left/right)', style: display(14)),
          Switch(
            value: _motion.flipRoll,
            activeThumbColor: C.lime,
            onChanged: (v) => setState(() => _motion.flipRoll = v),
          ),
        ]),
        Text('Tilt the phone left. If the cursor in Cemu goes right, switch this on.', style: mono(12)),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        _button(_sampling ? 'MEASURING...' : 'MEASURE GYRO', _sampling ? null : _measureGyro),
        const SizedBox(width: 8),
        _button('RESET', _reset),
        const SizedBox(width: 8),
        _button('SAVE MOTION', _saveMotion, primary: true),
      ]),
    ]);
  }
}
