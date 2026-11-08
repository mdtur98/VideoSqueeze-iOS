# ضاغط الفيديو — iOS

يضغط فيديوهات مكتبة الصور الأكبر من الحدّ إلى FHD بترميز HEVC، بنفس عدد الإطارات،
ويحفظ النسخة بنفس الاسم وتاريخ التصوير والموقع والمفضّلة والألبومات، ثم يحذف الأصول بتأكيد واحد.

## البناء
يُبنى تلقائياً على GitHub Actions (macOS) عند كل رفع — النتيجة `VideoSqueeze.ipa` غير موقّع
في تبويب Actions ← آخر تشغيل ← Artifacts. يُوقَّع ويُثبَّت بـ Sideloadly.

محلياً على Mac: `brew install xcodegen && xcodegen generate && open Squeeze.xcodeproj`
