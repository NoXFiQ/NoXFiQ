import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/auth_service.dart';
import 'services/product_service.dart';
import 'services/payment_service.dart';
import 'services/location_service.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/product/product_upload_screen.dart';
import 'screens/product/product_details_screen.dart';
import 'screens/payment/payment_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'utils/constants.dart';
import 'utils/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SokoKitaaApp());
}

class SokoKitaaApp extends StatelessWidget {
  const SokoKitaaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ProductService()),
        ChangeNotifierProvider(create: (_) => PaymentService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
      ],
      child: MaterialApp(
        title: 'Soko Kitaa',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.green,
          primaryColor: AppColors.primary,
          accentColor: AppColors.accent,
          fontFamily: 'CustomFont',
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('sw', 'TZ'), // Swahili - Tanzania
        ],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/otp': (context) => const OTPScreen(),
          '/home': (context) => const HomeScreen(),
          '/admin': (context) => const AdminDashboard(),
          '/product-upload': (context) => const ProductUploadScreen(),
          '/product-details': (context) => const ProductDetailsScreen(),
          '/payment': (context) => const PaymentScreen(),
          '/profile': (context) => const ProfileScreen(),
        },
      ),
    );
  }
}