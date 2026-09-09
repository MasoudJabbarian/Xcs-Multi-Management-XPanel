<p align="center">
<picture>
<img width="160" height="160" alt="Xcs" src="https://raw.githubusercontent.com/xpanel-cp/Xcs-Multi-Management-XPanel/master/xcslogo.png">
</picture>
</p>
<h1 align="center">Xcs</h1>
<h6 align="center">Xcs Multi Management XPanel</h6>

<p align="center">
	<a href="./EN-README.md">English</a> / <a href="./README.md">فارسی</a>
</p>

### فهرست
- [معرفی](#معرفی)
- [نصب](#نصب)
- [سازگاری Ubuntu 24.04](#سازگاری-ubuntu-2404)
- [فعال سازی SSL](#فعال-سازی-ssl)

## معرفی
وب اپلیکیشن Xcs مدیریت چندگانه سرورهای XPanel.

:green_circle: اتصال و مدیریت همزمان چند سرور از XPanel  
:green_circle: مدیریت کاربران تمامی سرورها  
:green_circle: افزودن پکیج  
:green_circle: ارائه اکانت نمایندگی  
:green_circle: مشاهده کاربران آنلاین  
:green_circle: تفکیک کاربران آنلاین برای هر نمایندگی  
:green_circle: بخش صورتحساب برای ادمین و نمایندگی  
:green_circle: امکان تغییر سرور متناسب با پکیج تعریف شده  
:green_circle: ارائه لینک اختصاصی مخصوص هر اکانت  
:green_circle: تنظیم پورت ورود برای پنل  

## نصب

### سیستم عامل
این شاخه برای **Ubuntu 24.04 LTS یا جدیدتر** آماده شده است.

- CPU: حداقل 3 هسته
- RAM: حداقل 2 GB
- Storage: حداقل 20 GB
- PHP: 8.3
- Apache: 2.4
- MariaDB/MySQL

برای نصب نسخه منتشرشده Xcs:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/xpanel-cp/Xcs-Multi-Management-XPanel/master/install.sh --ipv4)
```

> اگر از شاخه `ubuntu-24-support` در فورک خود استفاده می‌کنید، فایل `install.sh` همین شاخه را اجرا کنید.

### نکات مهم نصب
- اسکریپت نصب فقط روی Ubuntu 24.04+ اجرا می‌شود.
- PHP 8.1 دیگر به‌صورت hard-code نصب نمی‌شود؛ Ubuntu 24.04 از PHP 8.3 استفاده می‌کند.
- سرویس Apache با نام صحیح `apache2` مدیریت می‌شود.
- نصب‌کننده دیگر `crontab -r` را اجرا نمی‌کند و کرون‌های موجود را حذف نمی‌کند.
- کاربر دیتابیس پنل فقط روی دیتابیس Xcs دسترسی دارد و دسترسی `ALL ON *.*` دریافت نمی‌کند.
- `APP_DEBUG=false` در نصب production تنظیم می‌شود.
- endpoint نگهداری/انقضای کاربران با توکن داخلی محافظت می‌شود.

## سازگاری Ubuntu 24.04
Laravel 10 این پروژه با PHP 8.3 سازگار است، اما خود Laravel 10 اکنون به پایان دوره پشتیبانی رسیده است. ارتقای جداگانه به Laravel 11/نسخه جدیدتر باید به‌عنوان مرحله بعدی انجام شود و بدون تست کامل production انجام نشود.

## فعال سازی SSL
برای فعال سازی SSL می‌توانید از CDNهایی مانند Cloudflare استفاده کنید. بعد از اتصال دامنه به IP سرور، پروکسی CDN را فعال کنید تا اتصال با HTTPS برقرار شود. برای پورت پنل از یکی از پورت‌های مجاز CDN استفاده کنید و پورت‌های 80 و 443 را به‌عنوان پورت ورود خود پنل انتخاب نکنید.
