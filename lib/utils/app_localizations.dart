import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;
  
  AppLocalizations(this.locale);
  
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }
  
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();
  
  Map<String, String> _localizedStrings = {};
  
  Future<bool> load() async {
    String jsonString = await rootBundle.loadString('assets/translations/${locale.languageCode}.json');
    Map<String, dynamic> jsonMap = json.decode(jsonString);
    
    _localizedStrings = jsonMap.map((key, value) {
      return MapEntry(key, value.toString());
    });
    
    return true;
  }
  
  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }
  
  // Convenience methods for common translations
  String get appName => translate('app_name');
  String get appSlogan => translate('app_slogan');
  
  // Authentication
  String get login => translate('login');
  String get register => translate('register');
  String get logout => translate('logout');
  String get email => translate('email');
  String get password => translate('password');
  String get confirmPassword => translate('confirm_password');
  String get phoneNumber => translate('phone_number');
  String get fullName => translate('full_name');
  String get forgotPassword => translate('forgot_password');
  String get dontHaveAccount => translate('dont_have_account');
  String get alreadyHaveAccount => translate('already_have_account');
  
  // OTP
  String get otpTitle => translate('otp_title');
  String get otpSubtitle => translate('otp_subtitle');
  String get resendOTP => translate('resend_otp');
  String get verifyOTP => translate('verify_otp');
  
  // Products
  String get products => translate('products');
  String get addProduct => translate('add_product');
  String get editProduct => translate('edit_product');
  String get deleteProduct => translate('delete_product');
  String get price => translate('price');
  String get category => translate('category');
  String get description => translate('description');
  String get images => translate('images');
  String get sold => translate('sold');
  String get markAsSold => translate('mark_as_sold');
  String get viewDetails => translate('view_details');
  String get contactSeller => translate('contact_seller');
  
  // Location
  String get location => translate('location');
  String get currentLocation => translate('current_location');
  String get selectLocation => translate('select_location');
  String get region => translate('region');
  String get district => translate('district');
  String get ward => translate('ward');
  String get street => translate('street');
  
  // Payment
  String get payment => translate('payment');
  String get prePremium => translate('pre_premium');
  String get fullPremium => translate('full_premium');
  String get payNow => translate('pay_now');
  String get paymentSuccess => translate('payment_success');
  String get paymentFailed => translate('payment_failed');
  String get upgradeAccount => translate('upgrade_account');
  String get selectPaymentMethod => translate('select_payment_method');
  
  // General
  String get home => translate('home');
  String get profile => translate('profile');
  String get settings => translate('settings');
  String get about => translate('about');
  String get help => translate('help');
  String get search => translate('search');
  String get filter => translate('filter');
  String get sort => translate('sort');
  String get save => translate('save');
  String get cancel => translate('cancel');
  String get delete => translate('delete');
  String get edit => translate('edit');
  String get view => translate('view');
  String get share => translate('share');
  String get loading => translate('loading');
  String get noData => translate('no_data');
  String get error => translate('error');
  String get success => translate('success');
  String get warning => translate('warning');
  String get info => translate('info');
  
  // Validation Messages
  String get fieldRequired => translate('field_required');
  String get invalidEmail => translate('invalid_email');
  String get invalidPhone => translate('invalid_phone');
  String get passwordTooShort => translate('password_too_short');
  String get passwordsDoNotMatch => translate('passwords_do_not_match');
  
  // Premium Features
  String get premiumRequired => translate('premium_required');
  String get upgradeToView => translate('upgrade_to_view');
  String get dailyLimitReached => translate('daily_limit_reached');
  String get accountExpired => translate('account_expired');
  
  // Admin
  String get admin => translate('admin');
  String get users => translate('users');
  String get payments => translate('payments');
  String get reports => translate('reports');
  String get approvePayment => translate('approve_payment');
  String get rejectPayment => translate('reject_payment');
  String get suspendUser => translate('suspend_user');
  String get activateUser => translate('activate_user');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  
  @override
  bool isSupported(Locale locale) {
    return ['en', 'sw'].contains(locale.languageCode);
  }
  
  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }
  
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}