import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static regression guards. They do NOT prove absence of data leaks; see
/// docs/PRIVACY_AND_SECURITY.md for what is and is not covered.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('main manifest does not request network or microphone permission', () {
    expect(manifest, isNot(contains('android.permission.INTERNET')));
    expect(manifest, isNot(contains('android.permission.RECORD_AUDIO')));
  });

  test('OS cloud backup and device transfer are disabled for app data', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final block = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(rules)!.group(1)!;
      for (final d in ['root', 'file', 'database', 'sharedpref', 'external']) {
        expect(block, contains('<exclude domain="$d" />'), reason: '$section must exclude $d');
      }
    }
  });

  test('cleartext traffic is disallowed', () {
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
  });

  test('app source contains no networking or logging of content', () {
    final banned = RegExp(r"HttpClient|\bSocket\b|WebSocket|package:http/|package:dio/|Uri\.https?\(|\bprint\(|debugPrint\(|developer\.log\(|dart:developer");
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      if (banned.hasMatch(text)) hits.add(f.path);
    }
    expect(hits, isEmpty, reason: 'unexpected networking/logging in: $hits');
  });

  test('every free-text field disables keyboard suggestions and personalised learning', () {
    for (final path in ['lib/ui/session_screen.dart', 'lib/ui/missions_screen.dart']) {
      final src = File(path).readAsStringSync();
      final fields = RegExp(r'TextField\(').allMatches(src).length;
      expect(RegExp(r'enableIMEPersonalizedLearning: false').allMatches(src).length, fields, reason: path);
      expect(RegExp(r'autocorrect: false').allMatches(src).length, fields, reason: path);
      expect(RegExp(r'enableSuggestions: false').allMatches(src).length, fields, reason: path);
    }
  });
}
