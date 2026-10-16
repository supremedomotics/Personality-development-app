import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/database.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final db = AppDatabase(NativeDatabase(File(p.join(dir.path, 'ceo_forge.sqlite'))));
  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(DriftProgressRepository(db))],
    child: const CeoForgeApp(),
  ));
}

class CeoForgeApp extends StatelessWidget {
  const CeoForgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CEO Forge',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Tokens.light, Brightness.light),
        darkTheme: buildTheme(Tokens.dark, Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      );
}
