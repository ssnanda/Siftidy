import 'package:flutter/material.dart';
import 'library/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiftidyApp());
}

class SiftidyApp extends StatelessWidget {
  const SiftidyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Siftidy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF087E83),
          scaffoldBackgroundColor: const Color(0xFFF6F8F8),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            backgroundColor: Color(0xFFF6F8F8),
          ),
        ),
        home: const LibraryScreen(),
      );
}
