# LiveStar — Release Candidate 2.5

هذا المستودع هو نسخة Release Candidate من تطبيق LiveStar، مع Flutter للواجهة وNode.js/PostgreSQL للخلفية.

## ما تم تثبيته
- إصدار التطبيق: `2.5.0+25`
- تسجيل OTP: وضع التطوير مغلق افتراضياً ولا يتم إرجاع رمز OTP في الإنتاج.
- حماية HTTP: Helmet + CORS allow-list + حدود طلبات أساسية + حد لحجم JSON.
- الشحن: 8 باقات فقط، من 30,000 إلى 4,500,000 Coins، وأعلى باقة 600$.
- Diamonds: 1 Diamond لكل 60 Coins مشحونة، وتستخدم فقط لمتجر الإطارات وتغيير ID.
- VIP: 1–30، والتجديد 30 يوماً، والانخفاض درجة واحدة لكل دورة 30 يوماً بعد الانتهاء.
- الألعاب محذوفة من نطاق التطبيق.
- endpoint الاختبار الخاص بإضافة Coins وتجديد VIP أصبح مغلقاً عندما `ALLOW_TEST_BILLING=false`.
- LiveKit يستخدم عنوان `wss://` في بيئة الإنتاج.

## قبل أول Release فعلي
1. ثبّت Flutter SDK وAndroid SDK وXcode على جهاز البناء.
2. نفّذ `flutter create . --platforms=android,ios` مرة واحدة لإنشاء مجلدات المنصات الرسمية إذا لم تكن موجودة.
3. راجع `RELEASE_BUILD.md` و`android/key.properties.example`.
4. أنشئ keystore حقيقي خارج المستودع، ولا تضع كلمات المرور أو المفاتيح في Git.
5. اضبط `API_URL` إلى HTTPS فعلي عند البناء.
6. اضبط أسرار PostgreSQL/JWT/LiveKit في Secret Manager أو متغيرات البيئة.
7. اربط مزود SMS رسمي.
8. اربط بوابة دفع حقيقية عبر server-side webhook موثّق قبل تفعيل الشحن المالي.
9. اختبر الصوت/الفيديو على جهاز Android حقيقي وiPhone حقيقي مع TURN/SFU إنتاجي.

## أوامر البناء
### Android
`flutter pub get`
`flutter build appbundle --release --dart-define=API_URL=https://api.example.com`

### iOS
`flutter pub get`
`flutter build ipa --release --dart-define=API_URL=https://api.example.com`

> لا يمكن تنفيذ build/signing داخل هذه البيئة لأن Flutter/Android SDK/Xcode غير مثبتة. الملفات هنا مجهزة لتكون نقطة انطلاق Release Candidate، لكن التوقيع النهائي يجب أن يتم على جهاز/CI يملك مفاتيحك.
