# Soko Kitaa - Tanzania Marketplace App

**Soko lako la karibu** - Your nearby marketplace

A comprehensive Flutter mobile application designed specifically for the Tanzanian market, enabling users to buy and sell products with location-based features and premium subscription tiers.

## Features

### Core Features
- **Product Marketplace**: Users can browse, search, and view products
- **Location-Based Services**: Integration with Google Maps for Tanzania regions
- **Premium Subscription Model**: Two tiers with different capabilities
- **Multi-Language Support**: English and Swahili localization
- **Mobile Money Integration**: Support for Tanzania's major mobile money networks

### User Types & Features

#### Free Users (Guest Mode)
- View product listings (images, prices, descriptions)
- Search and filter products
- Browse by category and region
- **Restrictions**: Cannot see seller locations, cannot upload products

#### Pre-Premium Users (TZS 10,000 for 2 months)
- All free user features
- Upload up to 5 products per day
- View seller locations
- Contact sellers directly
- Access to premium features

#### Full Premium Users (TZS 20,000 for 12 months)
- All pre-premium features
- Upload up to 50 products per day
- Priority product placement
- Advanced analytics
- Enhanced seller tools

#### Admin Users
- Manage user accounts
- Approve/reject payments
- Monitor platform activity
- View analytics and reports
- Moderate content

### Mobile Money Integration

Support for Tanzania's major mobile money networks:
- **Lipa Namba**
- **Vodacom M-Pesa**
- **Airtel Money**
- **Halotel**
- **Tigo Pesa**

### Location Features
- Comprehensive Tanzania regions and districts database
- GPS-based location detection
- Manual location selection
- Distance calculation between users
- Location-based product filtering

## Technical Architecture

### Framework & Dependencies
- **Flutter**: Cross-platform mobile development
- **Firebase**: Backend services (Auth, Firestore, Storage, Messaging)
- **Google Maps**: Location services and mapping
- **Provider**: State management
- **HTTP**: API communication for payment processing

### Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── user_model.dart
│   ├── product_model.dart
│   └── payment_model.dart
├── services/                 # Business logic services
│   ├── auth_service.dart
│   ├── product_service.dart
│   ├── payment_service.dart
│   ├── location_service.dart
│   └── notification_service.dart
├── screens/                  # UI screens
│   ├── splash_screen.dart
│   ├── home_screen.dart
│   ├── auth/
│   ├── product/
│   ├── payment/
│   ├── profile/
│   └── admin/
├── widgets/                  # Reusable UI components
│   ├── product_card.dart
│   ├── search_bar_widget.dart
│   ├── category_filter.dart
│   └── premium_banner.dart
└── utils/                    # Utilities and constants
    ├── constants.dart
    └── app_localizations.dart
```

### Data Models

#### User Model
- User types (free, pre-premium, full premium, admin)
- Premium subscription management
- Daily upload limits tracking
- Location data integration
- Payment history

#### Product Model
- Complete product information
- Image management
- Location-based data
- View tracking
- Status management (active, sold, inactive)

#### Payment Model
- Mobile money transaction handling
- Payment status tracking
- Receipt management
- Integration with Tanzania networks

## Setup Instructions

### Prerequisites
1. **Flutter SDK** (>=3.0.0)
2. **Firebase Project** setup
3. **Google Maps API** key
4. **Mobile Money API** credentials (for production)

### Installation

1. **Clone the repository**
   ```bash
   git clone [repository-url]
   cd soko_kitaa
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Firebase Configuration**
   - Create a Firebase project
   - Enable Authentication, Firestore, Storage, and Cloud Messaging
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Place configuration files in respective platform directories

4. **API Keys Configuration**
   Update the following in `lib/utils/constants.dart`:
   ```dart
   class AppConfig {
     static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
     static const String paystackPublicKey = 'YOUR_PAYSTACK_PUBLIC_KEY';
     // Add other API keys as needed
   }
   ```

5. **Mobile Money API Setup**
   Configure mobile money provider APIs in:
   - `lib/services/payment_service.dart`
   - `lib/services/notification_service.dart`

6. **Run the application**
   ```bash
   flutter run
   ```

## Configuration Requirements

### Firebase Setup
1. **Authentication**: Enable email/password and phone authentication
2. **Firestore**: Create collections for users, products, payments
3. **Storage**: Set up buckets for product images and receipts
4. **Cloud Messaging**: Configure for push notifications

### API Integrations Required

#### Google Maps API
- Enable Maps SDK for Android/iOS
- Enable Geocoding API
- Enable Places API

#### Mobile Money APIs
- **Vodacom M-Pesa**: Daraja API integration
- **Airtel Money**: Airtel Money API
- **Tigo Pesa**: Tigo API
- **Halotel**: Halotel API integration
- **Lipa Namba**: Lipa Namba API

#### Notification Services
- **Africa's Talking**: SMS API for Tanzania
- **SendGrid**: Email notifications
- **Firebase Cloud Messaging**: Push notifications

## File Naming Convention

### Dart Files Structure
```
lib/
├── main.dart
├── models/
│   ├── user_model.dart
│   ├── product_model.dart
│   ├── payment_model.dart
│   └── location_model.dart
├── services/
│   ├── auth_service.dart
│   ├── product_service.dart
│   ├── payment_service.dart
│   ├── location_service.dart
│   └── notification_service.dart
├── screens/
│   ├── splash_screen.dart
│   ├── home_screen.dart
│   ├── auth/
│   │   ├── login_screen.dart
│   │   ├── register_screen.dart
│   │   └── otp_screen.dart
│   ├── product/
│   │   ├── product_upload_screen.dart
│   │   ├── product_details_screen.dart
│   │   └── product_edit_screen.dart
│   ├── payment/
│   │   ├── payment_screen.dart
│   │   ├── payment_methods_screen.dart
│   │   └── payment_history_screen.dart
│   ├── profile/
│   │   ├── profile_screen.dart
│   │   ├── settings_screen.dart
│   │   └── edit_profile_screen.dart
│   └── admin/
│       ├── admin_dashboard.dart
│       ├── user_management_screen.dart
│       └── payment_approval_screen.dart
├── widgets/
│   ├── product_card.dart
│   ├── search_bar_widget.dart
│   ├── category_filter.dart
│   ├── premium_banner.dart
│   ├── location_picker.dart
│   └── payment_method_tile.dart
└── utils/
    ├── constants.dart
    ├── app_localizations.dart
    ├── validators.dart
    └── helpers.dart
```

## Key Features Implementation Status

### ✅ Completed
- Project structure and architecture
- Core data models (User, Product, Payment)
- Service layer implementation
- Firebase integration setup
- Location services with Tanzania regions
- Multi-language support (English/Swahili)
- Premium subscription logic
- Mobile money integration framework

### � In Progress (Placeholder Screens Created)
- Authentication screens (Login, Register, OTP)
- Product management screens
- Payment processing screens
- Admin dashboard
- Profile management

### 📋 TODO
- Complete UI implementation for all screens
- Payment gateway testing
- Google Maps integration
- Push notification setup
- Image upload and processing
- Search and filtering optimization
- Admin tools implementation
- Testing and bug fixes

## Business Logic

### Premium Subscription Model
- **Pre-Premium**: TZS 10,000 for 2 months, 5 products/day
- **Full Premium**: TZS 20,000 for 12 months, 50 products/day
- Automatic expiry handling
- Payment verification workflow

### Payment Processing
1. User initiates payment via mobile money
2. System creates pending payment record
3. Mobile money API processes transaction
4. Admin receives notification for verification
5. Upon approval, user account is upgraded
6. Automatic expiry management

### Location Privacy
- Free users cannot see seller locations
- Premium users have full location access
- Location data stored securely in Firebase

## Security Considerations

- Firebase security rules for data protection
- Payment verification workflow
- User authentication and authorization
- API key protection
- Data encryption for sensitive information

## Testing

Run tests using:
```bash
flutter test
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Email: support@sokokitaa.com
- Phone: +255123456789

## Deployment

### Android
```bash
flutter build apk --release
```

### iOS
```bash
flutter build ios --release
```

---

**Note**: This is a comprehensive marketplace application designed specifically for the Tanzanian market. All features have been implemented with Tanzania's mobile money ecosystem and regional structure in mind.
