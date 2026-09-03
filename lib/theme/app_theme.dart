import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Flex Facility brand — navy & royal blue
  static const primary    = Color(0xFF1565C0);  // royal blue
  static const primaryDark= Color(0xFF0A1628);  // deep navy
  static const secondary  = Color(0xFF2196F3);  // sky blue
  static const accent     = Color(0xFF0288D1);  // light blue accent
  // Backgrounds
  static const background = Color(0xFFF5F8FF);  // clean white-blue
  static const surface    = Color(0xFFFFFFFF);
  static const surfaceVar = Color(0xFFEEF4FF);
  // Semantic
  static const success = Color(0xFF00897B);
  static const warning = Color(0xFFFF6B35);
  static const error   = Color(0xFFEF4444);
  static const info    = Color(0xFF2196F3);
  // Text
  static const textDark   = Color(0xFF0A1628);  // deep navy
  static const textMedium = Color(0xFF546E7A);  // blue-gray
  static const textLight  = Color(0xFF90A4AE);
  static const divider    = Color(0xFFDDE6F7);
  // Dark mode
  static const darkBackground = Color(0xFF0A1628);
  static const darkSurface    = Color(0xFF0D2137);
  static const darkSurfaceVar = Color(0xFF1A3550);
  static const darkDivider    = Color(0xFF1E3A5F);
  // Gradients
  static const gradientHero = LinearGradient(
    colors: [Color(0xFF0A1628), Color(0xFF1565C0), Color(0xFF2196F3)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const gradientPrimary = LinearGradient(
    colors: [Color(0xFF0A1628), Color(0xFF1565C0)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
}

class AppSpacing {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;
  static const double xxl = 48;
}

class AppRadius {
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 24.0;
  static const double full = 999.0;
}

class AppShadows {
  static List<BoxShadow> get card => [
    BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3)),
  ];
  static List<BoxShadow> get elevated => [
    BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8)),
    BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.04), blurRadius: 4,  offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> get primary => [
    BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
  ];
}

class AppTheme {
  static TextTheme _buildTextTheme() {
    // Barlow Condensed — bold athletic font matching the Flex Facility badge
    return GoogleFonts.barlowCondensedTextTheme().copyWith(
      displayLarge:  GoogleFonts.barlowCondensed(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.5),
      displayMedium: GoogleFonts.barlowCondensed(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textDark, letterSpacing: -0.3),
      titleLarge:    GoogleFonts.barlowCondensed(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark, letterSpacing: -0.2),
      titleMedium:   GoogleFonts.barlowCondensed(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
      titleSmall:    GoogleFonts.barlowCondensed(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark),
      bodyLarge:     GoogleFonts.barlow(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textDark),
      bodyMedium:    GoogleFonts.barlow(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textMedium),
      bodySmall:     GoogleFonts.barlow(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textLight),
      labelLarge:    GoogleFonts.barlowCondensed(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark, letterSpacing: 0.3),
      labelSmall:    GoogleFonts.barlowCondensed(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMedium, letterSpacing: 0.5),
    );
  }

  static ThemeData get light {
    final textTheme = _buildTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      textTheme: textTheme,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textDark,
        onError: Colors.white,
        surfaceContainerHighest: AppColors.surfaceVar,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: GoogleFonts.barlowCondensed(
            fontSize: 20, fontWeight: FontWeight.w700,
            color: AppColors.textDark, letterSpacing: -0.2),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.barlowCondensed(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.barlowCondensed(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.barlowCondensed(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textLight),
        labelStyle: const TextStyle(fontSize: 14, color: AppColors.textMedium),
        prefixIconColor: AppColors.textMedium,
        suffixIconColor: AppColors.textMedium,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primaryDark,
        contentTextStyle: GoogleFonts.barlow(fontSize: 14, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 4,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary.withValues(alpha: 0.4) : AppColors.divider),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVar,
        labelStyle: GoogleFonts.barlowCondensed(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMedium),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
        side: BorderSide.none,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.darkSurface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFFF8FAFC),
        onError: Colors.white,
        surfaceContainerHighest: AppColors.darkSurfaceVar,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.barlowCondensed(
            fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFFF8FAFC)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.barlowCondensed(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: AppColors.darkSurfaceVar,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.darkDivider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF546E7A)),
        labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF90A4AE)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.darkDivider, thickness: 1, space: 1),
    );
  }
}
