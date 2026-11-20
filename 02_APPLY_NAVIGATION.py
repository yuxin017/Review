from __future__ import annotations
from pathlib import Path
from datetime import datetime
import shutil
import subprocess
ROOT=Path.cwd().resolve()
P=Path('lib/park/visitor_navigation_page.dart')

def once(s,old,new):
    c=s.count(old)
    if c!=1: raise RuntimeError(f'Navigation anchor mismatch ({c} matches): {old[:95]!r}. NO FILES MODIFIED.')
    return s.replace(old,new,1)

def main():
    f=ROOT/P
    if not f.is_file():raise RuntimeError('Run from project root with pubspec.yaml.')
    branch=subprocess.run(['git','branch','--show-current'],capture_output=True,text=True,check=True).stdout.strip()
    if branch!='fix/staff-coverage-timetable':raise RuntimeError('Wrong branch: '+branch)
    raw=f.read_bytes(); s=raw.decode('utf-8-sig'); nl='\r\n' if b'\r\n' in raw else '\n'; s=s.replace('\r\n','\n')
    s=once(s,'  bool _mapReady = false;\n','  bool _mapReady = false;\n  bool _following = true;\n  bool _trackingStarting = false;\n  String? _trackingNotice;\n')
    s=once(s,'      if (here != null || widget.initialPosition != null) _trackPosition();',
           '      // A landmark start is also navigable: always request a live GPS stream.\n      unawaited(_startTracking());')
    start=s.index('  void _trackPosition() {\n')
    end=s.index('  bool _canGuide(Position? fix) =>',start)
    s=s[:start]+'''  /// The map follows any fresh on-campus fix with acceptable display accuracy.
  /// Turn-by-turn instructions and off-route detection keep the tighter 15m
  /// accuracy threshold to avoid false reroutes between campus buildings.
  Future<void> _startTracking() async {
    if (_trackingStarting || _liveLocation != null || !mounted) return;
    _trackingStarting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _trackingNotice =
            'Turn on device location to follow your movement.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _trackingNotice =
            'Allow location access to enable live map following.');
        return;
      }
      if (!mounted || _liveLocation != null) return;
      setState(() => _trackingNotice = null);
      _liveLocation = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen(
        (fix) {
          if (!mounted) return;
          _liveExpiry?.cancel();
          if (!_usable(fix)) {
            _clearLiveFix();
            return;
          }
          final guiding = _canGuide(fix) && !_loading && _path.isNotEmpty;
          setState(() {
            _liveFix = fix;
            _trackingNotice = null;
            if (guiding && !_arrived) {
              if (_liveInstruction + 1 < _maneuvers.length) {
                final next = _maneuvers[_liveInstruction + 1];
                if (next != null && VisitorGps.metres(fix, next) <= 15) {
                  _liveInstruction++;
                }
              }
              _instruction = _liveInstruction;
              _arrived = _liveInstruction + 1 >= _maneuvers.length &&
                  VisitorGps.metres(fix, _path.last) <= 12;
            }
          });
          // Follow independently of the precision required for spoken steps.
          if (!_loading && _path.isNotEmpty && VisitorGps.trusted(fix)) {
            _follow(fix);
          }
          if (guiding && !_arrived) {
            _checkForReroute(fix);
          } else {
            _offRouteFixes = 0;
          }
          final remaining = VisitorGps.maxAge -
              DateTime.now().difference(fix.timestamp).abs();
          if (remaining > Duration.zero) {
            _liveExpiry = Timer(remaining, _clearLiveFix);
          }
        },
        onError: (Object error) {
          if (mounted) setState(() => _trackingNotice =
              'Live location stopped. Check GPS and tap Retry Tracking.');
          _liveLocation = null;
          _clearLiveFix();
        },
        onDone: () {
          _liveLocation = null;
          _clearLiveFix();
        },
      );
    } catch (_) {
      if (mounted) setState(() => _trackingNotice =
          'Could not start live location. Check GPS permission and try again.');
    } finally {
      _trackingStarting = false;
    }
  }

''' +s[end:]
    s=once(s,'  void _follow(Position fix) {\n','  void _follow(Position fix) {\n    if (!_following) return;\n')
    s=once(s,'           if (!_loading) ...[\n','''           if (_trackingNotice != null) ...[
             const SizedBox(height: 8),
             Text(_trackingNotice!, style: const TextStyle(color: Color(0xFF9B602D))),
             TextButton.icon(
               onPressed: () => unawaited(_startTracking()),
               icon: const Icon(Icons.gps_fixed),
               label: const Text('Retry Tracking'),
             ),
           ],
           if (!_loading) ...[
             const SizedBox(height: 8),
             OutlinedButton.icon(
               onPressed: () {
                 setState(() => _following = !_following);
                 if (_following && _liveFix != null &&
                     VisitorGps.trusted(_liveFix)) {
                   _follow(_liveFix!);
                 }
               },
               icon: Icon(_following ? Icons.gps_fixed : Icons.gps_off),
               label: Text(_following ? 'Following My Location' : 'Resume Follow Me'),
             ),
''')
    if s.count('  Future<void> _startTracking() async {')!=1:raise RuntimeError('Navigation patch duplicated?')
    backup=ROOT.parent/('BeforeNavigationPatch_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    backup.mkdir(); shutil.copy2(f,backup/f.name)
    f.write_bytes((('\ufeff' if raw.startswith(b'\xef\xbb\xbf') else '')+s.replace('\n',nl)).encode('utf-8'))
    print('SUCCESS: Navigation GPS auto follow, landmark GPS stream, reroute precision safeguards updated.')
    print('Backup:',backup)
    print('Run flutter analyze; no Firebase deployment required for navigation.')

if __name__=='__main__': main()
