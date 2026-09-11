# LiveStar Release Build Checklist

## 1) Flutter
- Flutter stable مثبت ومُضاف إلى PATH.
- `flutter doctor` بدون أخطاء blocking.
- `flutter pub get`.
- `flutter analyze` يجب أن يمر بدون أخطاء.

## 2) API
ابنِ التطبيق مع عنوان API حقيقي:

```bash
flutter build appbundle --release --dart-define=API_URL=https://api.your-domain.com
```

لا تستخدم `10.0.2.2` أو HTTP في Release.

## 3) Android signing
1. أنشئ keystore على جهازك الآمن.
2. انسخ `android/key.properties.example` إلى `android/key.properties`.
3. ضع الملفين خارج Git/CI logs.
4. اربط قيم signing في `android/app/build.gradle` بعد إنشاء platform files بواسطة Flutter.

## 4) iOS signing
- افتح `ios/Runner.xcworkspace` بعد `flutter create . --platforms=ios`.
- اختر Team الصحيح.
- اضبط Bundle Identifier وSigning Certificate وProvisioning Profile.
- استخدم App Store Connect API/CI secrets إن كان البناء آلياً.

## 5) Backend production
- `NODE_ENV=production`
- `OTP_DEV_MODE=false`
- `ALLOW_TEST_BILLING=false`
- `JWT_SECRET` عشوائي وطويل (32+ bytes على الأقل).
- `CORS_ORIGINS` مقتصر على النطاقات المطلوبة.
- PostgreSQL ليس مكشوفاً للإنترنت مباشرة.
- LiveKit API secret محفوظ في Secret Manager.
- HTTPS/WSS مع شهادات صحيحة.
- مزود SMS رسمي.
- Webhook دفع موثق ومتحقق من التوقيع قبل إضافة Coins/Diamonds.

## 6) QA قبل المتجر
- OTP الحقيقي.
- إنشاء حساب وتسجيل الخروج/الدخول.
- شحن Coins عبر بوابة حقيقية.
- عدم إمكانية إنشاء Coins من العميل.
- هدية وخصم Coins ذري.
- Diamonds فقط للإطارات/ID.
- VIP expiration/decay.
- 20 مقعد مايك.
- TURN + LiveKit على شبكات 4G/5G وWi-Fi.
- حظر/كتم/طرد.
- crash reporting + monitoring.
- اختبار حمل وrate limiting.
