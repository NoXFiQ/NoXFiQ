import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user_model.dart';
import '../models/payment_model.dart';
import '../utils/constants.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  
  // Initialize notification service
  Future<void> initialize() async {
    await _firebaseMessaging.requestPermission();
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }
  
  // Get FCM token
  Future<String?> getToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }
  
  // Send welcome notification
  Future<void> sendWelcomeNotification(UserModel user) async {
    try {
      // Send email notification
      await _sendEmailNotification(
        to: user.email,
        subject: 'Karibu Soko Kitaa!',
        body: _getWelcomeEmailBody(user.fullName),
      );
      
      // Send SMS notification
      await _sendSMSNotification(
        phoneNumber: user.phoneNumber,
        message: 'Karibu Soko Kitaa! Akaunti yako imefunguliwa. Tunatumai utafurahia huduma zetu.',
      );
      
      // Send push notification
      await _sendPushNotification(
        title: 'Karibu Soko Kitaa!',
        body: 'Akaunti yako imefunguliwa kikamilifu.',
      );
    } catch (e) {
      debugPrint('Error sending welcome notification: $e');
    }
  }
  
  // Send payment notification to admin
  Future<void> sendPaymentNotificationToAdmin(PaymentModel payment) async {
    try {
      const adminEmail = AppConfig.adminEmail;
      const adminPhone = AppConfig.supportPhone;
      
      // Send email to admin
      await _sendEmailNotification(
        to: adminEmail,
        subject: 'Malipo Mapya - Soko Kitaa',
        body: _getPaymentEmailBody(payment),
      );
      
      // Send SMS to admin
      await _sendSMSNotification(
        phoneNumber: adminPhone,
        message: 'Malipo mapya: ${payment.userName} - ${payment.formattedAmount} - ${payment.methodName}',
      );
    } catch (e) {
      debugPrint('Error sending payment notification to admin: $e');
    }
  }
  
  // Send payment confirmation to user
  Future<void> sendPaymentConfirmation(PaymentModel payment) async {
    try {
      // Send email confirmation
      await _sendEmailNotification(
        to: payment.userName, // Assuming userName is email
        subject: 'Malipo Yamehakikiwa - Soko Kitaa',
        body: _getPaymentConfirmationEmailBody(payment),
      );
      
      // Send SMS confirmation
      await _sendSMSNotification(
        phoneNumber: payment.userPhone,
        message: 'Malipo yako ya ${payment.formattedAmount} yamehakikiwa. Akaunti yako imeimarishwa!',
      );
    } catch (e) {
      debugPrint('Error sending payment confirmation: $e');
    }
  }
  
  // Send OTP via SMS
  Future<bool> sendOTPViaSMS(String phoneNumber, String otp) async {
    try {
      await _sendSMSNotification(
        phoneNumber: phoneNumber,
        message: 'Msimbo wako wa uthibitisho ni: $otp. Usimalize haraka!',
      );
      return true;
    } catch (e) {
      debugPrint('Error sending OTP via SMS: $e');
      return false;
    }
  }
  
  // Send OTP via email
  Future<bool> sendOTPViaEmail(String email, String otp) async {
    try {
      await _sendEmailNotification(
        to: email,
        subject: 'Msimbo wa Uthibitisho - Soko Kitaa',
        body: _getOTPEmailBody(otp),
      );
      return true;
    } catch (e) {
      debugPrint('Error sending OTP via email: $e');
      return false;
    }
  }
  
  // Send product notification
  Future<void> sendProductNotification({
    required String title,
    required String message,
    required String userId,
  }) async {
    try {
      await _sendPushNotification(
        title: title,
        body: message,
        userId: userId,
      );
    } catch (e) {
      debugPrint('Error sending product notification: $e');
    }
  }
  
  // Send account status notification
  Future<void> sendAccountStatusNotification({
    required UserModel user,
    required bool isApproved,
  }) async {
    try {
      final title = isApproved ? 'Akaunti Imeidhinishwa' : 'Akaunti Imezuiwa';
      final message = isApproved 
          ? 'Akaunti yako imeidhinishwa. Unaweza sasa kutumia huduma zote.'
          : 'Akaunti yako imezuiwa. Wasiliana na msimamizi kwa maelezo zaidi.';
      
      await _sendEmailNotification(
        to: user.email,
        subject: title,
        body: message,
      );
      
      await _sendSMSNotification(
        phoneNumber: user.phoneNumber,
        message: message,
      );
    } catch (e) {
      debugPrint('Error sending account status notification: $e');
    }
  }
  
  // Send SMS notification
  Future<void> _sendSMSNotification({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      // Using a generic SMS API - replace with actual Tanzania SMS provider
      const apiUrl = 'https://api.africastalking.com/version1/messaging';
      const apiKey = 'YOUR_AFRICAS_TALKING_API_KEY';
      const username = 'YOUR_AFRICAS_TALKING_USERNAME';
      
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'apiKey': apiKey,
        },
        body: {
          'username': username,
          'to': phoneNumber,
          'message': message,
          'from': 'SOKO_KITAA',
        },
      );
      
      if (response.statusCode == 200) {
        debugPrint('SMS sent successfully');
      } else {
        debugPrint('SMS sending failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error sending SMS: $e');
    }
  }
  
  // Send email notification
  Future<void> _sendEmailNotification({
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      // Using a generic email API - replace with actual email service
      const apiUrl = 'https://api.sendgrid.com/v3/mail/send';
      const apiKey = 'YOUR_SENDGRID_API_KEY';
      
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'personalizations': [
            {
              'to': [
                {'email': to}
              ],
              'subject': subject,
            }
          ],
          'from': {'email': 'noreply@sokokitaa.com', 'name': 'Soko Kitaa'},
          'content': [
            {'type': 'text/html', 'value': body}
          ],
        }),
      );
      
      if (response.statusCode == 202) {
        debugPrint('Email sent successfully');
      } else {
        debugPrint('Email sending failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error sending email: $e');
    }
  }
  
  // Send push notification
  Future<void> _sendPushNotification({
    required String title,
    required String body,
    String? userId,
  }) async {
    try {
      // Using FCM for push notifications
      const fcmUrl = 'https://fcm.googleapis.com/fcm/send';
      const serverKey = 'YOUR_FCM_SERVER_KEY';
      
      final response = await http.post(
        Uri.parse(fcmUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverKey',
        },
        body: jsonEncode({
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
          },
          'data': {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'id': '1',
            'status': 'done',
          },
          'to': userId != null ? '/topics/user_$userId' : '/topics/all',
        }),
      );
      
      if (response.statusCode == 200) {
        debugPrint('Push notification sent successfully');
      } else {
        debugPrint('Push notification failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error sending push notification: $e');
    }
  }
  
  // Email templates
  String _getWelcomeEmailBody(String name) {
    return '''
    <html>
      <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
        <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
          <h2 style="color: #2E7D32;">Karibu Soko Kitaa!</h2>
          <p>Habari $name,</p>
          <p>Tunafurahi kukukaribisha kwenye Soko Kitaa - soko lako la karibu!</p>
          <p>Sasa unaweza:</p>
          <ul>
            <li>Kuona bidhaa mbalimbali</li>
            <li>Kuwasiliana na wauzaji</li>
            <li>Kuimarisha akaunti yako ili kuongeza bidhaa</li>
          </ul>
          <p>Kwa imarishaji ya akaunti, lipa tu TZS 10,000 kwa miezi 2 au TZS 20,000 kwa mwaka mzima.</p>
          <p>Asante kwa kuchagua Soko Kitaa!</p>
          <p style="color: #666;">Timu ya Soko Kitaa</p>
        </div>
      </body>
    </html>
    ''';
  }
  
  String _getPaymentEmailBody(PaymentModel payment) {
    return '''
    <html>
      <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
        <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
          <h2 style="color: #2E7D32;">Malipo Mapya</h2>
          <p><strong>Mtumiaji:</strong> ${payment.userName}</p>
          <p><strong>Simu:</strong> ${payment.userPhone}</p>
          <p><strong>Aina:</strong> ${payment.typeName}</p>
          <p><strong>Kiasi:</strong> ${payment.formattedAmount}</p>
          <p><strong>Njia:</strong> ${payment.methodName}</p>
          <p><strong>Rejeleo:</strong> ${payment.referenceNumber}</p>
          <p><strong>Tarehe:</strong> ${payment.createdAt.toString()}</p>
          <p>Tafadhali hakiki malipo haya na uimarishe akaunti ya mtumiaji.</p>
        </div>
      </body>
    </html>
    ''';
  }
  
  String _getPaymentConfirmationEmailBody(PaymentModel payment) {
    return '''
    <html>
      <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
        <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
          <h2 style="color: #2E7D32;">Malipo Yamehakikiwa!</h2>
          <p>Habari,</p>
          <p>Malipo yako ya ${payment.formattedAmount} yamehakikiwa kikamilifu.</p>
          <p><strong>Maelezo ya malipo:</strong></p>
          <ul>
            <li><strong>Aina:</strong> ${payment.typeName}</li>
            <li><strong>Kiasi:</strong> ${payment.formattedAmount}</li>
            <li><strong>Njia:</strong> ${payment.methodName}</li>
            <li><strong>Rejeleo:</strong> ${payment.referenceNumber}</li>
          </ul>
          <p>Akaunti yako imeimarishwa na unaweza sasa:</p>
          <ul>
            <li>Kuongeza bidhaa ${payment.type == PaymentType.prePremium ? '5' : '50'} kwa siku</li>
            <li>Kuona mahali pa wauzaji</li>
            <li>Kutumia huduma zote za premium</li>
          </ul>
          <p>Asante kwa kutumia Soko Kitaa!</p>
          <p style="color: #666;">Timu ya Soko Kitaa</p>
        </div>
      </body>
    </html>
    ''';
  }
  
  String _getOTPEmailBody(String otp) {
    return '''
    <html>
      <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
        <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
          <h2 style="color: #2E7D32;">Msimbo wa Uthibitisho</h2>
          <p>Msimbo wako wa uthibitisho ni:</p>
          <div style="background: #f5f5f5; padding: 20px; text-align: center; margin: 20px 0;">
            <h1 style="color: #2E7D32; font-size: 36px; margin: 0;">${otp}</h1>
          </div>
          <p>Ingiza msimbo huu kwenye programu ili kumaliza uthibitisho wako.</p>
          <p><strong>Kumbuka:</strong> Msimbo huu utaisha baada ya dakika 10.</p>
          <p style="color: #666;">Timu ya Soko Kitaa</p>
        </div>
      </body>
    </html>
    ''';
  }
}