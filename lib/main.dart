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
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF007980),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFF00676E),
            onPrimary: Colors.white,
            surface: const Color(0xFFFAFCFB),
            onSurface: const Color(0xFF162628),
            onSurfaceVariant: const Color(0xFF36474B),
          ),
          scaffoldBackgroundColor: const Color(0xFFF8FAF9),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            foregroundColor: Color(0xFF162628),
            backgroundColor: Color(0xFFF8FAF9),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF005F67),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00676E),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF005F67),
              side: const BorderSide(color: Color(0xFF9DAEB0)),
            ),
          ),
          textTheme: ThemeData.light().textTheme.apply(
            bodyColor: const Color(0xFF162628),
            displayColor: const Color(0xFF162628),
          ),
        ),
        home: const LibraryScreen(),
      );
}
