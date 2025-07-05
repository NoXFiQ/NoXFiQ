import 'package:flutter/material.dart';

// App Colors
class AppColors {
  static const Color primary = Color(0xFF2E7D32);
  static const Color accent = Color(0xFF66BB6A);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57C00);
  static const Color info = Color(0xFF1976D2);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color divider = Color(0xFFE0E0E0);
}

// App Strings
class AppStrings {
  static const String appName = 'Soko Kitaa';
  static const String appSlogan = 'Soko lako la karibu';
  
  // Authentication
  static const String login = 'Ingia';
  static const String register = 'Jisajili';
  static const String logout = 'Ondoka';
  static const String email = 'Barua pepe';
  static const String password = 'Nywila';
  static const String confirmPassword = 'Thibitisha nywila';
  static const String phoneNumber = 'Namba ya simu';
  static const String fullName = 'Jina kamili';
  static const String forgotPassword = 'Umesahau nywila?';
  static const String dontHaveAccount = 'Hauna akaunti?';
  static const String alreadyHaveAccount = 'Una akaunti?';
  
  // OTP
  static const String otpTitle = 'Thibitisha Namba';
  static const String otpSubtitle = 'Ingiza namba ya uthibitisho';
  static const String resendOTP = 'Tuma tena';
  static const String verifyOTP = 'Thibitisha';
  
  // Products
  static const String products = 'Bidhaa';
  static const String addProduct = 'Ongeza bidhaa';
  static const String editProduct = 'Hariri bidhaa';
  static const String deleteProduct = 'Futa bidhaa';
  static const String price = 'Bei';
  static const String category = 'Kategoria';
  static const String description = 'Maelezo';
  static const String images = 'Picha';
  static const String sold = 'Imeuzwa';
  static const String markAsSold = 'Weka imeuzwa';
  static const String viewDetails = 'Ona maelezo';
  static const String contactSeller = 'Wasiliana na muuzaji';
  
  // Location
  static const String location = 'Mahali';
  static const String currentLocation = 'Mahali pa sasa';
  static const String selectLocation = 'Chagua mahali';
  static const String region = 'Mkoa';
  static const String district = 'Wilaya';
  static const String ward = 'Kata';
  static const String street = 'Barabara';
  
  // Payment
  static const String payment = 'Malipo';
  static const String prePremium = 'Pre-Premium';
  static const String fullPremium = 'Full Premium';
  static const String payNow = 'Lipa sasa';
  static const String paymentSuccess = 'Malipo yamefanikiwa';
  static const String paymentFailed = 'Malipo yameshindwa';
  static const String upgradeAccount = 'Imarisha akaunti';
  static const String selectPaymentMethod = 'Chagua njia ya malipo';
  
  // General
  static const String home = 'Nyumbani';
  static const String profile = 'Profaili';
  static const String settings = 'Mipangilio';
  static const String about = 'Kuhusu';
  static const String help = 'Msaada';
  static const String search = 'Tafuta';
  static const String filter = 'Chuja';
  static const String sort = 'Panga';
  static const String save = 'Hifadhi';
  static const String cancel = 'Ghairi';
  static const String delete = 'Futa';
  static const String edit = 'Hariri';
  static const String view = 'Ona';
  static const String share = 'Shiriki';
  static const String loading = 'Inapakia...';
  static const String noData = 'Hakuna data';
  static const String error = 'Kosa';
  static const String success = 'Mafanikio';
  static const String warning = 'Onyo';
  static const String info = 'Taarifa';
  
  // Validation Messages
  static const String fieldRequired = 'Uwanda huu unahitajika';
  static const String invalidEmail = 'Barua pepe si sahihi';
  static const String invalidPhone = 'Namba ya simu si sahihi';
  static const String passwordTooShort = 'Nywila ni fupi sana';
  static const String passwordsDoNotMatch = 'Nywila hazifanani';
  
  // Premium Features
  static const String premiumRequired = 'Unahitaji akaunti ya premium';
  static const String upgradeToView = 'Imarisha ili kuona';
  static const String dailyLimitReached = 'Umefika kikomo cha bidhaa kwa siku';
  static const String accountExpired = 'Akaunti yako imeisha';
  
  // Admin
  static const String admin = 'Msimamizi';
  static const String users = 'Watumiaji';
  static const String payments = 'Malipo';
  static const String reports = 'Ripoti';
  static const String approvePayment = 'Idhinisha malipo';
  static const String rejectPayment = 'Kataa malipo';
  static const String suspendUser = 'Simamisha mtumiaji';
  static const String activateUser = 'Amilisha mtumiaji';
}

// App Configurations
class AppConfig {
  static const String firebaseProjectId = 'soko-kitaa';
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
  static const String paystackPublicKey = 'YOUR_PAYSTACK_PUBLIC_KEY';
  static const String adminEmail = 'admin@sokokitaa.com';
  static const String supportEmail = 'support@sokokitaa.com';
  static const String supportPhone = '+255123456789';
  
  // Storage paths
  static const String productImagesPath = 'products/images';
  static const String userProfilesPath = 'users/profiles';
  static const String paymentReceiptsPath = 'payments/receipts';
  
  // Collection names
  static const String usersCollection = 'users';
  static const String productsCollection = 'products';
  static const String paymentsCollection = 'payments';
  static const String categoriesCollection = 'categories';
  static const String locationsCollection = 'locations';
  
  // Limits
  static const int maxProductImages = 5;
  static const int maxImageSizeMB = 5;
  static const int maxProductsPerDay = 5;
  static const int maxProductsPerDayPremium = 50;
  static const int premiumDurationMonths = 2;
  static const int fullPremiumDurationMonths = 12;
  
  // Pricing
  static const double prePremiumPrice = 10000.0; // TZS
  static const double fullPremiumPrice = 20000.0; // TZS
  static const double promotionPrice = 5000.0; // TZS
}

// Tanzania Regions
class TanzaniaRegions {
  static const Map<String, List<String>> regions = {
    'Arusha': ['Arumeru', 'Arusha City', 'Arusha', 'Karatu', 'Longido', 'Meru', 'Monduli', 'Ngorongoro'],
    'Dar es Salaam': ['Ilala', 'Kinondoni', 'Temeke', 'Ubungo', 'Kigamboni'],
    'Dodoma': ['Bahi', 'Chamwino', 'Chemba', 'Dodoma Urban', 'Kondoa', 'Kongwa', 'Mpwapwa'],
    'Geita': ['Bukombe', 'Chato', 'Geita', 'Mbogwe', 'Nyang\'hwale'],
    'Iringa': ['Iringa Rural', 'Iringa Urban', 'Kilolo', 'Mafinga', 'Mufindi'],
    'Kagera': ['Biharamulo', 'Bukoba Rural', 'Bukoba Urban', 'Karagwe', 'Kyerwa', 'Misenyi', 'Muleba', 'Ngara'],
    'Katavi': ['Mlele', 'Mpanda', 'Nsimbo'],
    'Kigoma': ['Buhigwe', 'Kakonko', 'Kasulu', 'Kibondo', 'Kigoma Rural', 'Kigoma Urban', 'Uvinza'],
    'Kilimanjaro': ['Hai', 'Moshi Rural', 'Moshi Urban', 'Mwanga', 'Rombo', 'Same', 'Siha'],
    'Lindi': ['Kilifi', 'Lindi Rural', 'Lindi Urban', 'Liwale', 'Nachingwea', 'Ruangwa'],
    'Manyara': ['Babati', 'Hanang', 'Kiteto', 'Mbulu', 'Simanjiro'],
    'Mara': ['Bunda', 'Butiama', 'Musoma Rural', 'Musoma Urban', 'Rorya', 'Serengeti', 'Tarime'],
    'Mbeya': ['Busokelo', 'Chunya', 'Ileje', 'Kyela', 'Mbarali', 'Mbeya Rural', 'Mbeya Urban', 'Momba', 'Rungwe'],
    'Morogoro': ['Gairo', 'Kilombero', 'Kilosa', 'Morogoro Rural', 'Morogoro Urban', 'Mvomero', 'Ulanga'],
    'Mtwara': ['Masasi', 'Mtwara Rural', 'Mtwara Urban', 'Nanyumbu', 'Newala', 'Tandahimba'],
    'Mwanza': ['Ilemela', 'Kwimba', 'Magu', 'Misungwi', 'Nyamagana', 'Sengerema', 'Ukerewe'],
    'Njombe': ['Ludewa', 'Makambako', 'Makete', 'Njombe Rural', 'Njombe Urban', 'Wanging\'ombe'],
    'Pwani': ['Bagamoyo', 'Chalinze', 'Kibaha', 'Kisarawe', 'Mkuranga', 'Rufiji'],
    'Rukwa': ['Kalambo', 'Nkasi', 'Sumbawanga Rural', 'Sumbawanga Urban'],
    'Ruvuma': ['Madaba', 'Mbinga', 'Namtumbo', 'Nyasa', 'Songea Rural', 'Songea Urban', 'Tunduru'],
    'Shinyanga': ['Kahama', 'Kishapu', 'Maswa', 'Meatu', 'Shinyanga Rural', 'Shinyanga Urban'],
    'Simiyu': ['Bariadi', 'Busega', 'Itilima', 'Maswa', 'Meatu'],
    'Singida': ['Ikungi', 'Iramba', 'Manyoni', 'Mkalama', 'Singida Rural', 'Singida Urban'],
    'Tabora': ['Igunga', 'Kaliua', 'Nzega', 'Sikonge', 'Tabora Urban', 'Urambo', 'Uyui'],
    'Tanga': ['Handeni', 'Kilifi', 'Korogwe', 'Lushoto', 'Mkinga', 'Muheza', 'Pangani', 'Tanga City'],
    'Pemba North': ['Micheweni', 'Wete'],
    'Pemba South': ['Chake Chake', 'Mkoani'],
    'Zanzibar North': ['Kaskazini A', 'Kaskazini B'],
    'Zanzibar South': ['Kati', 'Kusini', 'Mjini Magharibi'],
    'Zanzibar West': ['Magharibi'],
  };
  
  static List<String> get allRegions => regions.keys.toList();
  
  static List<String> getDistricts(String region) {
    return regions[region] ?? [];
  }
}